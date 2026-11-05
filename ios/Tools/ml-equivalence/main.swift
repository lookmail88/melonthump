import AVFoundation
import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String) { if !cond { failures += 1; print("FAIL:", msg) } }

// ---------- 1. bundled file == compiled-in constants ----------
let bundled = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try! Data(contentsOf: bundled)
let model = try! ModelFileLoader.load(data: data, source: .bundled, allowReservedId: true) as! HeuristicBandsModel
check(model.parameters == .babyV22, "bundled baby-1.0.ml != babyV22")
check(model.descriptor.displayName == "Baby 1.0" && model.descriptor.modelId == "baby-1.0", "descriptor")
// Bit-level comparison of every field via Mirror.
let a = Mirror(reflecting: model.parameters).children, b = Mirror(reflecting: HeuristicBandsParameters.babyV22).children
for (x, y) in zip(a, b) {
    if let dx = x.value as? Double, let dy = y.value as? Double { check(dx.bitPattern == dy.bitPattern, "bits \(x.label!)") }
    if let ix = x.value as? Int, let iy = y.value as? Int { check(ix == iy, "int \(x.label!)") }
}
print("params fields:", a.count)

// ---------- 2. validation rules ----------
let base = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
func variant(_ f: (inout [String: Any]) -> Void) -> Data {
    var o = base; o["modelId"] = "test-1"; f(&o); return try! JSONSerialization.data(withJSONObject: o)
}
func params(_ f: @escaping (inout [String: Any]) -> Void) -> Data {
    variant { o in var p = o["parameters"] as! [String: Any]; f(&p); o["parameters"] = p }
}
func expectFail(_ d: Data, _ name: String) {
    do { _ = try ModelFileLoader.load(data: d, source: .external("x.ml"), allowReservedId: false); check(false, "accepted: \(name)") }
    catch { print("  rejected \(name): \(error)") }
}
func expectOK(_ d: Data, _ name: String) {
    do { _ = try ModelFileLoader.load(data: d, source: .external("x.ml"), allowReservedId: false); print("  accepted \(name)") }
    catch { check(false, "rejected: \(name) \(error)") }
}
expectOK(variant { _ in }, "valid external copy")
expectOK(variant { $0["futureField"] = ["x": 1]; $0["notes"] = "hi" }, "unknown fields ignored")
expectOK(variant { $0["modelId"] = "baby-2.0.1" }, "dotted id")
expectFail(Data(count: 64 * 1024 + 1), "65 KB")
expectFail(Data("not json".utf8), "not JSON")
expectFail(Data("[1,2]".utf8), "top-level array")
expectFail(Data([0xff, 0xfe, 0x00]), "binary")
expectFail(variant { $0.removeValue(forKey: "displayName") }, "missing displayName")
expectFail(variant { $0.removeValue(forKey: "parameters") }, "missing parameters")
expectFail(variant { $0["formatVersion"] = 2 }, "formatVersion 2")
expectFail(variant { $0["formatVersion"] = "1" }, "formatVersion string")
expectFail(variant { $0["modelId"] = "Baby" }, "uppercase id")
expectFail(variant { $0["modelId"] = "a b" }, "space in id")
expectFail(variant { $0["modelId"] = "" }, "empty id")
expectFail(variant { $0["modelId"] = "baby-1.0" }, "reserved id from external")
expectFail(variant { $0["kind"] = "coreml" }, "unknown kind")
expectFail(variant { $0["displayName"] = 5 }, "displayName number")
expectFail(params { $0.removeValue(forKey: "crestDbMin") }, "missing crestDbMin")
expectFail(params { $0["crestDbMin"] = "18" }, "string param")
expectFail(params { $0["crestDbMin"] = true }, "bool param")
expectFail(params { $0["overripeBelowHz"] = 300 }, "overripe >= ripe")
expectFail(params { $0["overripeBelowHz"] = 0 }, "overripe 0")
expectFail(params { $0["ripeUpToHz"] = 2001 }, "ripe > 2000")
expectOK(params { $0["ripeUpToHz"] = 2000 }, "ripe == 2000")
expectFail(params { $0["envelopeFramesPerSecond"] = 0 }, "zero frame rate")
expectFail(params { $0["envelopeFramesPerSecond"] = 100.5 }, "fractional int param")
expectFail(params { $0["bandMinHz"] = 700 }, "band inverted")

// ---------- 3. folder scan: order, duplicates, reserved, invalid ----------
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mlscan-\(UUID())")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
try! variant { $0["modelId"] = "dup"; $0["displayName"] = "First" }.write(to: dir.appendingPathComponent("a.ml"))
try! variant { $0["modelId"] = "dup"; $0["displayName"] = "Second" }.write(to: dir.appendingPathComponent("b.ml"))
try! variant { $0["modelId"] = "baby-1.0" }.write(to: dir.appendingPathComponent("c.ml"))
try! Data("{".utf8).write(to: dir.appendingPathComponent("d.ml"))
try! variant { $0["modelId"] = "other" }.write(to: dir.appendingPathComponent("e.ml"))
try! variant { $0["modelId"] = "ignored" }.write(to: dir.appendingPathComponent("f.json"))
try! Data(count: 70_000).write(to: dir.appendingPathComponent("g.ml"))
let scan = ModelFileLoader.scan(folder: dir, taken: ["baby-1.0"])
check(scan.models.first?.descriptor.displayName == "First", "first file in name order wins")
check(scan.models.map { $0.descriptor.modelId } == ["dup", "other"], "scan ids")
check(scan.skipped.count == 4, "skipped \(scan.skipped)")
print("scan:", scan.models.map { $0.descriptor.modelId }, "skipped:", scan.skipped.map { "\($0.0): \($0.1)" })

// ---------- 4. v2.2 equivalence on synthetic recordings ----------
var rng = SystemRandomNumberGenerator()
func rand(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &rng) }
func signal(sr: Int, seconds: Double, kind: Int) -> [Double] {
    let n = Int(Double(sr) * seconds)
    var s = [Double](repeating: 0, count: n)
    let noise = rand(0.0001...0.004)
    for i in 0..<n { s[i] = noise * rand(-1...1) }
    let onset = Int(rand(0.1...(seconds - 0.4)) * Double(sr))
    switch kind {
    case 0, 1, 2: // damped resonance (the real thump), varied
        let f = kind == 0 ? rand(80...520) : (kind == 1 ? [159.5, 160.0, 160.5, 279.5, 280.0, 280.5].randomElement()! : rand(140...330))
        let amp = rand(0.003...0.6), tau = rand(0.02...0.6)
        for i in onset..<n { let t = Double(i - onset) / Double(sr); s[i] += amp * exp(-t / tau) * sin(2 * .pi * f * t) }
    case 3: // click
        for i in onset..<min(n, onset + 20) { s[i] += rand(-0.8...0.8) }
    case 4: // broadband knock
        let amp = rand(0.01...0.5)
        for i in onset..<min(n, onset + sr / 20) { s[i] += amp * rand(-1...1) * exp(-Double(i - onset) / Double(sr) / 0.01) }
    default: // two tones
        let f1 = rand(100...400), f2 = rand(100...400), amp = rand(0.01...0.5)
        for i in onset..<n { let t = Double(i - onset) / Double(sr); s[i] += amp * exp(-t / 0.15) * (sin(2 * .pi * f1 * t) + 0.8 * sin(2 * .pi * f2 * t)) }
    }
    return s
}
func writeWav(_ s: [Double], sr: Int) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("eq-\(UUID()).wav")
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sr), channels: 1, interleaved: false)!
    let file = try! AVAudioFile(forWriting: url, settings: fmt.settings)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count))!
    buf.frameLength = AVAudioFrameCount(s.count)
    for i in 0..<s.count { buf.floatChannelData![0][i] = Float(s[i]) }
    try! file.write(from: buf)
    return url
}
var compared = 0, verdicts: [String: Int] = [:]
for trial in 0..<Int(CommandLine.arguments[2])! {
    let sr = [44100, 48000, 16000][trial % 3]
    let secs = [3.0, 5.0, 8.0][(trial / 3) % 3]
    let url = writeWav(signal(sr: sr, seconds: secs, kind: trial % 6), sr: sr)
    defer { try? FileManager.default.removeItem(at: url) }
    let old = try? LocalAnalyzerV22.analyze(audioURL: url)
    let new = try? model.analyze(audioURL: url)
    compared += 1
    guard let o = old, let nn = new else { check(old == nil && new == nil, "throw mismatch \(trial)"); continue }
    verdicts[o.verdict, default: 0] += 1
    let same = o.verdict == nn.verdict
        && o.dominantFrequencyHz.bitPattern == nn.dominantFrequencyHz.bitPattern
        && o.spectralCentroidHz.bitPattern == nn.spectralCentroidHz.bitPattern
        && o.decayTimeMs.bitPattern == nn.decayTimeMs.bitPattern
        && o.confidence.bitPattern == nn.confidence.bitPattern
        && o.debugSummary == nn.debugSummary
    check(same, "trial \(trial): \(o) vs \(nn)")
}
print("equivalence trials:", compared, "verdicts:", verdicts)
print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
exit(failures == 0 ? 0 : 1)
