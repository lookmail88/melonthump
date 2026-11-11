import Foundation
// Drives the PRODUCTION RecorderReadiness.isInputReady predicate.
var fails = 0, checks = 0
func check(_ name: String, _ sampleRate: Double, _ channels: UInt32, _ available: Bool, expect: Bool) {
    checks += 1
    let got = RecorderReadiness.isInputReady(sampleRate: sampleRate, channelCount: channels, inputAvailable: available)
    if got == expect {
        print("  ✓ \(name): \(got ? "ready" : "not ready")")
    } else {
        fails += 1
        print("  ✗ FAIL \(name): got \(got), expected \(expect)")
    }
}
check("valid 48 kHz mono, input available", 48_000, 1, true, expect: true)
check("valid 44.1 kHz stereo, input available", 44_100, 2, true, expect: true)
check("sampleRate 0", 0, 1, true, expect: false)
check("channelCount 0", 48_000, 0, true, expect: false)
check("inputAvailable false", 48_000, 1, false, expect: false)
check("all invalid (post-ad state)", 0, 0, false, expect: false)
check("negative sampleRate", -1, 1, true, expect: false)
check("NaN sampleRate", .nan, 1, true, expect: false)
print()
if fails > 0 { print("RESULT: \(fails) of \(checks) checks FAILED"); exit(1) }
print("RESULT: all \(checks) checks passed")
