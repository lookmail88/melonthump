import Foundation
// Promo-gate harness (2026-11-06). Each process run = one app launch of
// the PRODUCTION CreditWallet.swift; state persists in this tool's own
// UserDefaults domain between runs, exactly as across a real relaunch.
//   harness reset                      wipe the domain (fresh install)
//   harness seed key=bool ...          pre-set legacy flags (upgrade)
//   POLICY=promo|post|freeday|fail harness launch t[:watch] ...
// Each t = one thump attempt that, if allowed, completes with a RIPE
// verdict (u = UNKNOWN verdict). ":watch" = if gated, watch the ad
// (completes) then thump; ":credit" = if gated, pay the ad-free price. Prints the TapView-equivalent decision.
let args = Array(CommandLine.arguments.dropFirst())
let domain = ProcessInfo.processInfo.processName
switch args.first {
case "reset":
    UserDefaults.standard.removePersistentDomain(forName: domain)
    print("reset: fresh install")
case "seed":
    for kv in args.dropFirst() {
        let p = kv.split(separator: "=")
        UserDefaults.standard.set(p[1] == "true", forKey: String(p[0]))
    }
    print("seeded \(args.dropFirst().joined(separator: " "))")
case "launch":
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let w = CreditWallet.shared
        await w.refreshPolicy(environment: .prod)
        print("launch POLICY=\(ProcessInfo.processInfo.environment["POLICY"] ?? "promo") lifetime=\(w.lifetimeAnalyses) balance=\(w.balance) firstFreeUsed=\(w.firstFreeUsed)")
        for (i, a) in args.dropFirst().enumerated() {
            let parts = a.split(separator: ":")
            let verdict = parts[0] == "u" ? "UNKNOWN" : "RIPE"
            let action = parts.count > 1 ? String(parts[1]) : ""
            let before = w.lifetimeAnalyses
            var line = "  thump#\(i + 1) (lifetime before=\(before)) "
            if !w.canThump {
                // TapView.toggleRecording: promo gate vs session gate alert.
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
            print(line + " → \(verdict) recorded, lifetime=\(w.lifetimeAnalyses)")
        }
        print("  end: balance=\(w.balance) firstFreeUsed=\(w.firstFreeUsed) sessionUnlocked=\(w.sessionUnlocked)")
        sem.signal()
    }
    while sem.wait(timeout: .now() + 0.01) == .timedOut { RunLoop.main.run(until: Date() + 0.01) }
default:
    print("usage: see header")
}
