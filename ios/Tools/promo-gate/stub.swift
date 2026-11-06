import Foundation
// Minimal stand-ins so the production CreditWallet.swift compiles as a
// macOS command-line tool. The "server" policy comes from $POLICY.
enum ServerEnvironment: String { case prod, dev }
enum Ripeness: String {
    case unripe = "UNRIPE", ripe = "RIPE", overripe = "OVERRIPE", unknown = "UNKNOWN"
}
struct ClientVersion {
    let creditPerAd: Int?
    let promoEndsAtEpochMillis: Int64?
    let initialFreeThumps: Int?
    let sessionUnlockEnabled: Bool?
    let adFreeSessionCreditPrice: Int?
}
struct PolicyError: Error {}
struct APIClient {
    let environment: ServerEnvironment
    func fetchClientVersion(currentVersion: String) async throws -> ClientVersion {
        let future = Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000
        switch ProcessInfo.processInfo.environment["POLICY"] ?? "promo" {
        case "promo":   return ClientVersion(creditPerAd: 1, promoEndsAtEpochMillis: future,
                                             initialFreeThumps: nil, sessionUnlockEnabled: nil, adFreeSessionCreditPrice: nil)
        case "post":    return ClientVersion(creditPerAd: 1, promoEndsAtEpochMillis: nil,
                                             initialFreeThumps: 2, sessionUnlockEnabled: true, adFreeSessionCreditPrice: 1)
        case "freeday": return ClientVersion(creditPerAd: -1, promoEndsAtEpochMillis: future,
                                             initialFreeThumps: nil, sessionUnlockEnabled: nil, adFreeSessionCreditPrice: nil)
        default: throw PolicyError()
        }
    }
}
