import AppTrackingTransparency
import Foundation
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// AdMob plumbing: UMP consent, ATT, SDK start, and rewarded ads.
///
/// The rewarded unit ID comes from Info.plist
/// (`MelonThumpRewardedAdUnitID`), filled by build settings from
/// Config.xcconfig — Google's public test IDs by default; the real IDs
/// live only in the gitignored Secrets.xcconfig on the build machine.
@MainActor
final class AdsManager: NSObject, ObservableObject {
    static let shared = AdsManager()

    @Published private(set) var rewardedReady = false

    private var rewardedAd: RewardedAd?
    private var rewardContinuation: CheckedContinuation<Bool, Never>?
    private var bootstrapped = false

    /// Rewarded unit issued by the server on the attested version
    /// policy fetch (1.1.0). Wins over the Info.plist value when set;
    /// the real ID never ships in the binary or in git.
    private var serverRewardedUnitID: String?

    /// Google public test rewarded unit, kept as the last-resort
    /// literal if the config value below is somehow missing.
    private static let testRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"

    /// Fallback unit from build settings (DEFAULT_ADMOB_REWARDED_UNIT_ID
    /// in Config/Secrets, surfaced via Info.plist): if the configured
    /// unit fails to load, we retry with this one (the Google test unit
    /// always fills) so the promo gate never locks the user out over a
    /// no-fill.
    private static var fallbackRewardedUnitID: String {
        Bundle.main.object(forInfoDictionaryKey: "MelonThumpDefaultRewardedAdUnitID") as? String
            ?? testRewardedUnitID
    }

    private var rewardedUnitID: String {
        serverRewardedUnitID
            ?? Bundle.main.object(forInfoDictionaryKey: "MelonThumpRewardedAdUnitID") as? String
            ?? Self.fallbackRewardedUnitID
    }

    /// Where a unit came from, for the stats ledger (closed set in
    /// design doc §3.3: server / test_fallback). Anything that did not
    /// come from the server counts as the local fallback chain.
    private func unitSource(for unitID: String) -> String {
        unitID == serverRewardedUnitID ? "server" : "test_fallback"
    }

    /// Applies the server-issued rewarded unit ID from the attested
    /// policy fetch; re-preloads with it when the SDK is already up.
    func applyServerRewardedUnitId(_ unitID: String) {
        guard !unitID.isEmpty, unitID != serverRewardedUnitID else { return }
        serverRewardedUnitID = unitID
        if bootstrapped {
            Task { await preloadRewarded() }
        }
    }

    /// Consent → ATT → SDK start → first rewarded preload. Idempotent.
    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        Task { await runBootstrap() }
    }

    private func runBootstrap() async {
        await requestConsent()
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { _ in done.resume() }
        }
        await preloadRewarded()
    }

    private func requestConsent() async {
        let params = RequestParameters()
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: params)
            if ConsentInformation.shared.formStatus == .available,
               ConsentInformation.shared.consentStatus == .required,
               let vc = Self.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: vc)
            }
        } catch {
            // Consent is best-effort: ads still serve, non-personalized.
        }
    }

    // MARK: - Rewarded

    func preloadRewarded() async {
        if await loadRewarded(unitID: rewardedUnitID) { return }
        // Configured unit failed (reason logged in loadRewarded). Fall
        // back to the Google test unit so there is almost always an ad
        // ready to show.
        if rewardedUnitID != Self.fallbackRewardedUnitID {
            _ = await loadRewarded(unitID: Self.fallbackRewardedUnitID)
        }
    }

    @discardableResult
    private func loadRewarded(unitID: String) async -> Bool {
        Task { await StatsReporter.shared.recordAdRequested(unitSource: unitSource(for: unitID)) }
        do {
            let ad = try await RewardedAd.load(with: unitID, request: Request())
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            rewardedReady = true
            Task { await StatsReporter.shared.recordAdLoaded() }
            return true
        } catch {
            rewardedAd = nil
            rewardedReady = false
            print("[AdsManager] Rewarded load failed (unit \(unitID)): \(error)")
            Task { await StatsReporter.shared.recordAdLoadFailed(errorCode: (error as NSError).code) }
            return false
        }
    }

    /// Presents the preloaded rewarded ad. Returns true only when the
    /// user watched to the end and earned the reward. When no ad is
    /// ready it kicks off a preload and returns false.
    func showRewarded() async -> Bool {
        guard let ad = rewardedAd, let vc = Self.topViewController() else {
            await preloadRewarded()
            return false
        }
        rewardedAd = nil
        rewardedReady = false
        return await withCheckedContinuation { continuation in
            rewardContinuation = continuation
            ad.present(from: vc) { [weak self] in
                Task { await StatsReporter.shared.recordAdRewarded() }
                self?.resolveReward(true)
            }
        }
    }

    private func resolveReward(_ earned: Bool) {
        rewardContinuation?.resume(returning: earned)
        rewardContinuation = nil
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

// MARK: - FullScreenContentDelegate

extension AdsManager: FullScreenContentDelegate {
    nonisolated func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        Task { await StatsReporter.shared.recordAdShown() }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { await StatsReporter.shared.recordAdDismissed() }
        Task { @MainActor in
            // Closed without earning → the pending show resolves false.
            if rewardContinuation != nil { resolveReward(false) }
            await preloadRewarded()
        }
    }

    nonisolated func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        Task { @MainActor in
            if rewardContinuation != nil { resolveReward(false) }
            await preloadRewarded()
        }
    }
}
