import Foundation
// Minimal stand-ins so the production CreditWallet.swift compiles as a
// macOS command-line tool. The "server" policy comes from $POLICY, the
// policy's initialFreeThumps (N) from $FREE (unset = policy omits it →
// built-in default 2), and the running app version from $APP_VERSION.
enum ServerEnvironment: String { case prod, dev }
enum Ripeness: String {
    case unripe = "UNRIPE", ripe = "RIPE", overripe = "OVERRIPE", unknown = "UNKNOWN"
}
/// Production reads CFBundleShortVersionString; the harness simulates
/// an upgrade by launching with a different $APP_VERSION.
enum AppIdentity {
    static var appVersion: String { ProcessInfo.processInfo.environment["APP_VERSION"] ?? "1.2.0" }
}
struct ClientVersion {
    let creditPerAd: Int?
    let promoEndsAtEpochMillis: Int64?
    let initialFreeThumps: Int?
    let sessionUnlockEnabled: Bool?
    let adFreeSessionCreditPrice: Int?
    /// 2.0 field; the harness policies never send it (older-server shape).
    var adExempt: Bool? = nil
}
struct PolicyError: Error {}
struct APIClient {
    let environment: ServerEnvironment
    func fetchClientVersion(currentVersion: String) async throws -> ClientVersion {
        let future = Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000
        let free = ProcessInfo.processInfo.environment["FREE"].flatMap { Int($0) }
        switch ProcessInfo.processInfo.environment["POLICY"] ?? "promo" {
        case "promo":   return ClientVersion(creditPerAd: 1, promoEndsAtEpochMillis: future,
                                             initialFreeThumps: free, sessionUnlockEnabled: nil, adFreeSessionCreditPrice: nil)
        case "post":    return ClientVersion(creditPerAd: 1, promoEndsAtEpochMillis: nil,
                                             initialFreeThumps: free ?? 2, sessionUnlockEnabled: true, adFreeSessionCreditPrice: 1)
        case "freeday": return ClientVersion(creditPerAd: -1, promoEndsAtEpochMillis: future,
                                             initialFreeThumps: free, sessionUnlockEnabled: nil, adFreeSessionCreditPrice: nil)
        default: throw PolicyError()
        }
    }
}
