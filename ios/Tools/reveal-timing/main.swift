import Foundation
// Drives the PRODUCTION RevealTiming.remaining(elapsed:minimum:).
// Own fixtures only; no app state.
var fails = 0, checks = 0
func check(_ name: String, elapsed: TimeInterval, minimum: TimeInterval, expect: TimeInterval) {
    checks += 1
    let got = RevealTiming.remaining(elapsed: elapsed, minimum: minimum)
    if abs(got - expect) < 1e-9 {
        print("  ✓ \(name): \(got) s")
    } else {
        fails += 1
        print("  ✗ FAIL \(name): got \(got), expected \(expect)")
    }
}
check("production minimum is 1.2 s", elapsed: 0, minimum: RevealTiming.minimum, expect: 1.2)
check("elapsed 0 -> full minimum", elapsed: 0, minimum: 1.2, expect: 1.2)
check("elapsed 0.3 of 1.2 -> 0.9", elapsed: 0.3, minimum: 1.2, expect: 0.9)
check("elapsed 1.1 of 1.2 -> 0.1", elapsed: 1.1, minimum: 1.2, expect: 0.1)
check("elapsed == minimum -> 0", elapsed: 1.2, minimum: 1.2, expect: 0)
check("elapsed > minimum (1.5) -> 0", elapsed: 1.5, minimum: 1.2, expect: 0)
check("elapsed far beyond (60 s) -> 0", elapsed: 60, minimum: 1.2, expect: 0)
check("negative elapsed (-0.5) -> clamped to minimum", elapsed: -0.5, minimum: 1.2, expect: 1.2)
check("negative elapsed (-100) -> clamped to minimum", elapsed: -100, minimum: 1.2, expect: 1.2)
check("NaN elapsed -> minimum", elapsed: .nan, minimum: 1.2, expect: 1.2)
check("minimum 0 -> 0", elapsed: 0, minimum: 0, expect: 0)
check("negative minimum -> 0", elapsed: 0, minimum: -1, expect: 0)
print()
if fails > 0 { print("RESULT: \(fails) of \(checks) checks FAILED"); exit(1) }
print("RESULT: all \(checks) checks passed")
