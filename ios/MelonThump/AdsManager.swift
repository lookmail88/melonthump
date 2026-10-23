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

    private var rewardedUnitID: String {
        Bundle.main.object(forInfoDictionaryKey: "MelonThumpRewardedAdUnitID") as? String
            ?? "ca-app-pub-3940256099942544/1712485313"  // Google test rewarded unit
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
        do {
            let ad = try await RewardedAd.load(with: rewardedUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            rewardedReady = true
        } catch {
            rewardedAd = nil
            rewardedReady = false
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
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
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
