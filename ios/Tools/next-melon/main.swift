import Foundation
// Next-melon harness (2026-11-06, 1.2): drives the PRODUCTION
// CreditWallet.swift (with ../promo-gate/stub.swift) through
// result → "Thump Another Melon" → next thump, in ONE app session.
//   harness reset
//   [APP_VERSION=..] [FREE=N] POLICY=promo|post harness launch tok...
// tokens: t / u      thump (if allowed) → RIPE / UNKNOWN verdict
//         t:watch    if gated, watch the ad (unlocks session), then thump
//         t:credit   if gated, pay the ad-free price, then thump
//         n          "Thump Another Melon" on the result screen
// TapView.startNextMelon() references no wallet/ads API (run.sh checks
// its source), so its wallet-visible effect is nothing: `n` takes a
// full wallet snapshot before and after that point and reports whether
// a single field moved.
let args = Array(CommandLine.arguments.dropFirst())
let domain = ProcessInfo.processInfo.processName

@MainActor func snapshot(_ w: CreditWallet) -> String {
    "versionCount=\(w.versionAnalyses) sessionUnlocked=\(w.sessionUnlocked) canThump=\(w.canThump)"
    + " needsPromoAd=\(w.needsPromoAd) needsSessionUnlock=\(w.needsSessionUnlock)"
    + " promoFreeRemaining=\(w.promoFreeRemaining) balance=\(w.balance) firstFreeUsed=\(w.firstFreeUsed)"
}

switch args.first {
case "reset":
    UserDefaults.standard.removePersistentDomain(forName: domain)
    print("reset: fresh install")
case "launch":
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let w = CreditWallet.shared
        await w.refreshPolicy(environment: .prod)
        print("launch POLICY=\(ProcessInfo.processInfo.environment["POLICY"] ?? "promo") N=\(w.initialFreeThumps) \(snapshot(w))")
        var onResult = false
        var i = 0
        for a in args.dropFirst() {
            if a == "n" {
                guard onResult else { print("  nav: not on a result screen"); continue }
                let before = snapshot(w)
                // ← TapView.startNextMelon(): screen state only, no wallet call.
                onResult = false
                let after = snapshot(w)
                print("  nav  next-melon: wallet \(before == after ? "UNCHANGED" : "CHANGED") (\(after))")
                continue
            }
            i += 1
            let parts = a.split(separator: ":")
            let verdict = parts[0] == "u" ? "UNKNOWN" : "RIPE"
            let action = parts.count > 1 ? String(parts[1]) : ""
            var line = "  thump#\(i) (versionCount before=\(w.versionAnalyses)) "
            if !w.canThump {
                line += w.needsPromoAd ? "→ PROMO AD GATE" : "→ SESSION GATE"
                if action == "watch" {
                    w.unlockSessionWithAd()
                    line += " → ad watched, session unlocked"
                } else if action == "credit", w.needsSessionUnlock, w.unlockSessionWithCredits() {
                    line += " → paid credit, session unlocked"
                } else { print(line + " (declined)"); continue }
            } else {
                line += w.nextThumpIsPromoFree ? "→ no gate (promo freebie)" : "→ no gate"
            }
            w.recordAnalysis(verdict: verdict)
            onResult = true
            print(line + " → \(verdict) recorded, versionCount=\(w.versionAnalyses)")
        }
        print("  end: \(snapshot(w))")
        sem.signal()
    }
    while sem.wait(timeout: .now() + 0.01) == .timedOut { RunLoop.main.run(until: Date() + 0.01) }
default:
    print("usage: see header")
}
