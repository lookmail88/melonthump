import Foundation

/// The latest server policy seen this launch, shared by the views that
/// depend on it (design doc 1.2.0 §2/§3).
@MainActor
final class PolicyStore: ObservableObject {
    static let shared = PolicyStore()

    /// Server selector visibility (design doc §2, owner answers
    /// 2026-11-05): shown only on Xcode builds, and only when this
    /// app's version equals the server-published TestFlight version and
    /// differs from the published Product version. Hidden on any
    /// mismatch, missing field, or fetch failure; TestFlight and App
    /// Store builds never show it and stay locked to Prod.
    @Published private(set) var serverSelectorUnlocked = false

    private init() {}

    /// Evaluated against the PROD policy — the published versions are a
    /// production release fact, and evaluating them on prod keeps a
    /// build that is pointed at Dev from hiding its own way back.
    func applyProdPolicy(_ policy: ClientVersion?) {
        serverSelectorUnlocked = Self.selectorUnlocked(
            channel: AppIdentity.channel, appVersion: AppIdentity.appVersion,
            testflightVersion: policy?.testflightVersion, productVersion: policy?.productVersion)
    }

    #if DEBUG
    /// Screenshot stage only: render the selector as if unlocked.
    func debugForceSelector() { serverSelectorUnlocked = true }
    #endif

    nonisolated static func selectorUnlocked(channel: String, appVersion: String,
                                             testflightVersion: String?, productVersion: String?) -> Bool {
        guard channel == "xcode", let testflightVersion, let productVersion else { return false }
        return appVersion == testflightVersion && appVersion != productVersion
    }
}
