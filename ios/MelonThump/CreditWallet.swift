import Foundation

/// Local credit wallet — the balance stays on-device (client-trusted).
/// The server is the source of truth only for invite confirmations;
/// their rewards land here exactly once per claim.
///
/// Precedence of the rules, top to bottom:
///
/// 1. Free day (policy creditPerAd == -1): unlimited use for the rest
///    of that local day, no ads.
/// 2. Launch promo (promoEndsAtEpochMillis in the future): credits are
///    neither needed nor spent. A user whose lifetime count of real
///    analyses is below initialFreeThumps (default 2) thumps with no ad
///    (decided 2026-11-06) — these promo freebies ARE the lifetime
///    "first two free" allowance, so they use up the post-promotion one
///    below rather than adding to it. From then on the 1.1.0 rule: the
///    first thump after each fresh launch needs one completed rewarded
///    ad, which unlocks the session.
/// 3. Post-promotion economy (design doc 1.2.0 §3, decided 2026-11-05),
///    for every user, new and existing alike:
///    - the first real (non-UNKNOWN) analysis is never charged;
///    - a one-time grant of (initialFreeThumps − 1) credits covers the
///      next one(s) — 1 credit with the default of 2;
///    - after that, the session gate: one rewarded ad unlocks
///      unlimited thumps until the app exits (it re-arms on relaunch);
///      a user with balance may instead spend adFreeSessionCreditPrice
///      credits to unlock the session with no ad. A gate ad earns no
///      credits. With sessionUnlockEnabled == false there is no gate.
///    All numbers come from the server policy, with the design values
///    built in and used whenever the policy cannot be fetched.
///
/// Lifetime analysis count: real (non-UNKNOWN) completed analyses in
/// any mode, persisted from 1.2.0 on. Earlier releases kept no such
/// count, so App Store 1.0.0/1.1.0 upgraders start from zero (seeded to
/// 1 only when a 1.2.0 flag proves a real analysis happened).
///
/// 1.2.0 drops the v1 welcome grant of 5 for new installs (superseded
/// by the allowance above); existing balances are kept.
@MainActor
final class CreditWallet: ObservableObject {
    /// One wallet per process: the home screen and the invite flow
    /// (reward claims) share it.
    static let shared = CreditWallet()
    @Published private(set) var balance: Int
    @Published private(set) var creditPerAd: Int = 1
    /// Bumped whenever the free-day flag flips so views re-render.
    @Published private(set) var freeDayStamp: String?
    /// Promo window end from the latest policy fetch (nil = no promo).
    @Published private(set) var promoEndsAt: Date?
    /// Session-only unlock (promo gate or post-promotion gate): never
    /// persisted, so an app relaunch always gates again.
    @Published private(set) var sessionUnlocked = false
    @Published private(set) var firstFreeUsed: Bool
    /// Real (non-UNKNOWN) analyses completed on this install, lifetime.
    @Published private(set) var lifetimeAnalyses: Int
    /// How many of those were promo freebies (ad-free under the promo
    /// because lifetimeAnalyses was below initialFreeThumps).
    private var promoFreebiesUsed: Int
    // Allowance policy (server-tunable; design defaults built in).
    @Published private(set) var initialFreeThumps = CreditWallet.defaultInitialFreeThumps
    @Published private(set) var sessionUnlockEnabled = CreditWallet.defaultSessionUnlockEnabled
    @Published private(set) var adFreeSessionCreditPrice = CreditWallet.defaultAdFreeSessionCreditPrice

    static let defaultInitialFreeThumps = 2
    static let defaultSessionUnlockEnabled = true
    static let defaultAdFreeSessionCreditPrice = 1

    private let defaults = UserDefaults.standard

    private enum Key {
        static let balance = "credit.balance"
        static let welcomed = "credit.welcomed"
        static let freeDay = "credit.freeDay"      // yyyy-MM-dd, local time
        static let firstFreeUsed = "allowance.firstFreeUsed"
        static let allowanceGranted = "allowance.granted"
        static let appliedClaims = "credit.appliedClaimIds"
        static let lifetimeAnalyses = "analysis.lifetimeCount"
        static let promoFreebiesUsed = "allowance.promoFreebiesUsed"
        /// Written by InviteManager on the first real analysis (1.2.0).
        static let inviteFirstThumpDone = "invite.firstThumpDone"
    }

    private init() {
        if !defaults.bool(forKey: Key.welcomed) {
            // 1.2.0: no welcome grant any more; mark the install so a
            // later version never mistakes it for a 1.1.0 newcomer.
            defaults.set(true, forKey: Key.welcomed)
        }
        balance = defaults.integer(forKey: Key.balance)
        freeDayStamp = defaults.string(forKey: Key.freeDay)
        firstFreeUsed = defaults.bool(forKey: Key.firstFreeUsed)
        promoFreebiesUsed = defaults.integer(forKey: Key.promoFreebiesUsed)
        if defaults.object(forKey: Key.lifetimeAnalyses) == nil {
            // First run with the counter. No release before 1.2.0 kept a
            // per-analysis count; the only reliable earlier evidence is
            // the 1.2.0 "a real analysis happened" flags — at least 1.
            let seen = defaults.bool(forKey: Key.firstFreeUsed)
                || defaults.bool(forKey: Key.inviteFirstThumpDone)
            defaults.set(seen ? 1 : 0, forKey: Key.lifetimeAnalyses)
        }
        lifetimeAnalyses = defaults.integer(forKey: Key.lifetimeAnalyses)
    }

    var isFreeDay: Bool { freeDayStamp == Self.todayString }
    var isPromoActive: Bool {
        guard let promoEndsAt else { return false }
        return Date() < promoEndsAt
    }
    /// The post-promotion economy applies (not promo, not free day).
    var economyActive: Bool { !isFreeDay && !isPromoActive }

    /// Promo freebies still available: the lifetime count (BEFORE the
    /// next analysis) is below initialFreeThumps — counts 0 and 1 with
    /// the default of 2.
    var promoFreeRemaining: Int { max(0, initialFreeThumps - lifetimeAnalyses) }
    /// The next thump is a promo freebie (no ad, session not unlocked).
    var nextThumpIsPromoFree: Bool {
        isPromoActive && !isFreeDay && !sessionUnlocked && promoFreeRemaining > 0
    }
    /// Promo gate: one completed ad unlocks this app session — once the
    /// lifetime promo freebies are used up.
    var needsPromoAd: Bool {
        isPromoActive && !isFreeDay && !sessionUnlocked && promoFreeRemaining == 0
    }
    /// Post-promotion gate: free thump used and the session not yet unlocked.
    var needsSessionUnlock: Bool {
        economyActive && sessionUnlockEnabled && firstFreeUsed && !sessionUnlocked
    }
    var canPayAdFree: Bool { balance >= adFreeSessionCreditPrice }
    var canThump: Bool { !needsPromoAd && !needsSessionUnlock }
    /// The next thump is the never-charged first one.
    var nextThumpIsFirstFree: Bool { economyActive && !firstFreeUsed && !sessionUnlocked }

    /// Adopts the server policy. A -1 creditPerAd starts a free day that
    /// lasts until local midnight. Fail-open: when the policy cannot be
    /// fetched, the built-in defaults stay in force.
    func refreshPolicy(environment: ServerEnvironment) async {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard let policy = try? await APIClient(environment: environment)
            .fetchClientVersion(currentVersion: version) else {
            grantAllowanceIfDue()
            return
        }
        creditPerAd = policy.creditPerAd ?? 1
        if creditPerAd == -1, freeDayStamp != Self.todayString {
            defaults.set(Self.todayString, forKey: Key.freeDay)
            freeDayStamp = Self.todayString
        }
        promoEndsAt = policy.promoEndsAtEpochMillis.map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        }
        initialFreeThumps = max(0, policy.initialFreeThumps ?? Self.defaultInitialFreeThumps)
        sessionUnlockEnabled = policy.sessionUnlockEnabled ?? Self.defaultSessionUnlockEnabled
        adFreeSessionCreditPrice = max(1, policy.adFreeSessionCreditPrice ?? Self.defaultAdFreeSessionCreditPrice)
        if initialFreeThumps == 0 && !firstFreeUsed {
            // A policy of zero free thumps: nothing is on the house.
            markFirstFreeUsed()
        }
        grantAllowanceIfDue()
    }

    /// The one-time grant of (initialFreeThumps − 1) credits, given once
    /// per install when the post-promotion economy first applies. Promo
    /// freebies beyond the first already covered thumps this grant is
    /// for, so they are deducted (no double grant): 2 promo freebies
    /// with the default of 2 → 0 credits; 1 → firstFree used, 1 credit.
    private func grantAllowanceIfDue() {
        guard economyActive, !defaults.bool(forKey: Key.allowanceGranted) else { return }
        defaults.set(true, forKey: Key.allowanceGranted)
        add(max(0, initialFreeThumps - 1 - max(0, promoFreebiesUsed - 1)))
    }

    /// Unlocks this app session (after a completed gate/promo ad — no
    /// credits are earned for it).
    func unlockSessionWithAd() {
        sessionUnlocked = true
    }

    /// Spends the ad-free price to unlock this app session.
    @discardableResult
    func unlockSessionWithCredits() -> Bool {
        guard canPayAdFree else { return false }
        balance -= adFreeSessionCreditPrice
        defaults.set(balance, forKey: Key.balance)
        sessionUnlocked = true
        return true
    }

    /// Records a completed analysis. Only real (non-UNKNOWN) verdicts
    /// count: each one bumps the lifetime count (any mode). In the
    /// post-promotion economy the first one uses up the free first
    /// thump; under the promo, one taken as a promo freebie (count was
    /// below initialFreeThumps, session not unlocked) uses up the same
    /// lifetime allowance.
    func recordAnalysis(verdict: String) {
        guard verdict != Ripeness.unknown.rawValue else { return }
        let wasPromoFree = nextThumpIsPromoFree
        lifetimeAnalyses += 1
        defaults.set(lifetimeAnalyses, forKey: Key.lifetimeAnalyses)
        if wasPromoFree {
            promoFreebiesUsed += 1
            defaults.set(promoFreebiesUsed, forKey: Key.promoFreebiesUsed)
            if !firstFreeUsed { markFirstFreeUsed() }
            return
        }
        guard economyActive, !sessionUnlocked else { return }
        if !firstFreeUsed { markFirstFreeUsed() }
    }

    private func markFirstFreeUsed() {
        firstFreeUsed = true
        defaults.set(true, forKey: Key.firstFreeUsed)
    }

    /// Adds invite-reward credits exactly once per server claim id.
    @discardableResult
    func applyClaim(id: UUID, credits: Int) -> Bool {
        var applied = Set(defaults.stringArray(forKey: Key.appliedClaims) ?? [])
        guard !applied.contains(id.uuidString) else { return false }
        applied.insert(id.uuidString)
        defaults.set(Array(applied), forKey: Key.appliedClaims)
        add(max(0, credits))
        return true
    }

    private func add(_ credits: Int) {
        guard credits > 0 else { return }
        balance += credits
        defaults.set(balance, forKey: Key.balance)
    }

    private static var todayString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
