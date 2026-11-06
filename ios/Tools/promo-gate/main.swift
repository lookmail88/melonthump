import Foundation
// Promo-gate harness (2026-11-06). Each process run = one app launch of
// the PRODUCTION CreditWallet.swift; state persists in this tool's own
// UserDefaults domain between runs, exactly as across a real relaunch.
//   harness reset                      wipe the domain (fresh install)
//   harness seed key=value ...         pre-set keys (true/false → Bool,
//                                      digits → Int, else String)
//   harness dump                       print the wallet's counter keys
//   [APP_VERSION=x.y.z] [FREE=N] POLICY=promo|post|freeday|fail harness launch t[:watch] ...
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
        let k = String(p[0]), v = String(p[1])
        if v == "true" || v == "false" { UserDefaults.standard.set(v == "true", forKey: k) }
        else if let i = Int(v) { UserDefaults.standard.set(i, forKey: k) }
        else { UserDefaults.standard.set(v, forKey: k) }
    }
    print("seeded \(args.dropFirst().joined(separator: " "))")
case "dump":
    let d = UserDefaults.standard
    for k in ["analysis.countVersion", "analysis.versionCount", "analysis.lifetimeCount",
              "allowance.promoFreebiesUsed", "allowance.firstFreeUsed", "allowance.granted", "credit.balance"] {
        print("  \(k) = \(d.object(forKey: k).map { "\($0)" } ?? "<absent>")")
    }
case "launch":
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let w = CreditWallet.shared
        await w.refreshPolicy(environment: .prod)
        let env = ProcessInfo.processInfo.environment
        print("launch v\(w.countedVersion) POLICY=\(env["POLICY"] ?? "promo") N=\(w.initialFreeThumps) versionCount=\(w.versionAnalyses) balance=\(w.balance) firstFreeUsed=\(w.firstFreeUsed)")
        for (i, a) in args.dropFirst().enumerated() {
            let parts = a.split(separator: ":")
            let verdict = parts[0] == "u" ? "UNKNOWN" : "RIPE"
            let action = parts.count > 1 ? String(parts[1]) : ""
            let before = w.versionAnalyses
            var line = "  thump#\(i + 1) (versionCount before=\(before)) "
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
            print(line + " → \(verdict) recorded, versionCount=\(w.versionAnalyses)")
        }
        print("  end: balance=\(w.balance) firstFreeUsed=\(w.firstFreeUsed) sessionUnlocked=\(w.sessionUnlocked)")
        sem.signal()
    }
    while sem.wait(timeout: .now() + 0.01) == .timedOut { RunLoop.main.run(until: Date() + 0.01) }
default:
    print("usage: see header")
}
