import Foundation

/// Local credit wallet — v1 keeps the balance on-device (client-trusted,
/// rate-limited). The server-side ledger from the design doc replaces
/// this in a later phase; the rules stay the same:
///
/// - One completed analysis costs 1 credit (an UNKNOWN "too noisy"
///   result is not charged — the caller enforces that).
/// - Watching a rewarded ad to the end grants `creditPerAd`, the value
///   the server's version policy currently advertises.
/// - creditPerAd == -1 declares a free day: unlimited use for the rest
///   of that local day, and no ads are offered.
/// - While the server-advertised promo window (promoEndsAtEpochMillis)
///   is running, the credit economy is suspended: the first thump
///   after each fresh app launch requires one completed rewarded ad,
///   which unlocks unlimited use until the app exits. The unlock is
///   memory-only — relaunching always gates again, even the same day.
/// - New installs receive a one-time welcome grant so the app is usable
///   out of the box; ad grants are capped per day (v1 anti-abuse).
@MainActor
final class CreditWallet: ObservableObject {
    @Published private(set) var balance: Int
    @Published private(set) var creditPerAd: Int = 1
    @Published private(set) var grantsToday: Int = 0
    /// Bumped whenever the free-day flag flips so views re-render.
    @Published private(set) var freeDayStamp: String?
    /// Promo window end from the latest policy fetch (nil = no promo).
    @Published private(set) var promoEndsAt: Date?
    /// Session-only promo unlock: never persisted, so an app relaunch
    /// always gates again — exactly the promo's daily-first-open feel.
    @Published private(set) var promoUnlocked = false

    static let welcomeGrant = 5
    static let dailyAdCap = 10

    private let defaults = UserDefaults.standard

    private enum Key {
        static let balance = "credit.balance"
        static let welcomed = "credit.welcomed"
        static let freeDay = "credit.freeDay"      // yyyy-MM-dd, local time
        static let grantDay = "credit.grantDay"    // yyyy-MM-dd, local time
        static let grantCount = "credit.grantCount"
    }

    init() {
        if !defaults.bool(forKey: Key.welcomed) {
            defaults.set(Self.welcomeGrant, forKey: Key.balance)
            defaults.set(true, forKey: Key.welcomed)
        }
        balance = defaults.integer(forKey: Key.balance)
        freeDayStamp = defaults.string(forKey: Key.freeDay)
        rollGrantDay()
    }

    var isFreeDay: Bool { freeDayStamp == Self.todayString }
    var isPromoActive: Bool {
        guard let promoEndsAt else { return false }
        return Date() < promoEndsAt
    }
    /// Promo gate: one completed ad unlocks this app session.
    var needsPromoAd: Bool { isPromoActive && !isFreeDay && !promoUnlocked }
    var canThump: Bool {
        if needsPromoAd { return false }
        return isFreeDay || promoUnlocked || balance > 0
    }
    var canEarnFromAd: Bool {
        !isPromoActive && !isFreeDay && creditPerAd > 0 && grantsToday < Self.dailyAdCap
    }

    /// Adopts the server policy's creditPerAd. A -1 starts a free day
    /// that lasts until local midnight (the stored date stops matching).
    func refreshPolicy(environment: ServerEnvironment) async {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard let policy = try? await APIClient(environment: environment)
            .fetchClientVersion(currentVersion: version) else { return }
        creditPerAd = policy.creditPerAd ?? 1
        if creditPerAd == -1, freeDayStamp != Self.todayString {
            defaults.set(Self.todayString, forKey: Key.freeDay)
            freeDayStamp = Self.todayString
        }
        promoEndsAt = policy.promoEndsAtEpochMillis.map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        }
    }

    /// Unlocks the promo for this app session after a completed ad.
    func unlockPromoForSession() {
        promoUnlocked = true
    }

    /// Charges one analysis. Free days and promo days never charge.
    @discardableResult
    func spendOne() -> Bool {
        if isFreeDay || isPromoActive { return true }
        guard balance > 0 else { return false }
        balance -= 1
        defaults.set(balance, forKey: Key.balance)
        return true
    }

    /// Grants the reward after a completed rewarded ad.
    @discardableResult
    func grantFromAd() -> Bool {
        rollGrantDay()
        guard canEarnFromAd else { return false }
        balance += creditPerAd
        grantsToday += 1
        defaults.set(balance, forKey: Key.balance)
        defaults.set(grantsToday, forKey: Key.grantCount)
        return true
    }

    private func rollGrantDay() {
        if defaults.string(forKey: Key.grantDay) != Self.todayString {
            defaults.set(Self.todayString, forKey: Key.grantDay)
            defaults.set(0, forKey: Key.grantCount)
            grantsToday = 0
        } else {
            grantsToday = defaults.integer(forKey: Key.grantCount)
        }
    }

    private static var todayString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
