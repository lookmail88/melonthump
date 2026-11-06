import AVFoundation
import Foundation

// Recognition-chain diagnosis harness. See run.sh for usage.
//
// Everything below the signal generators is measurement only: the
// analysis itself is the production LocalAnalyzer.analyze(samples:...)
// with HeuristicBandsParameters.babyV22 (Baby 1.0 == heuristic v2.2).
// The "knockout" table re-runs with ONE gate disabled at a time — a
// sensitivity probe for this report, not a proposed parameter set.

// MARK: - Deterministic RNG (SplitMix64)

struct RNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func u() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func r(_ a: Double, _ b: Double) -> Double { a + (b - a) * u() }
    mutating func i(_ a: Int, _ b: Int) -> Int { a + Int(next() % UInt64(b - a + 1)) }
    mutating func gauss() -> Double {
        let u1 = max(u(), 1e-12), u2 = u()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

// MARK: - DSP helpers

let SR = 48_000          // iPhone input node format (48 kHz Float32)
let SECONDS = 5.0        // default Listening Duration (Settings: 3/5/8 s)

func db(_ x: Double) -> Double { 20 * log10(max(x, 1e-12)) }
func undb(_ d: Double) -> Double { pow(10, d / 20) }

struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    /// RBJ cookbook 2nd-order high-pass.
    static func highpass(_ f: Double, q: Double = 0.7071) -> Biquad {
        let w = 2 * Double.pi * f / Double(SR), c = cos(w), al = sin(w) / (2 * q), a0 = 1 + al
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - al) / a0)
    }
    static func lowpass(_ f: Double, q: Double = 0.7071) -> Biquad {
        let w = 2 * Double.pi * f / Double(SR), c = cos(w), al = sin(w) / (2 * q), a0 = 1 + al
        return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - al) / a0)
    }
    func apply(_ x: [Double]) -> [Double] {
        var y = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for n in 0..<x.count {
            let v = b0 * x[n] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[n]; y2 = y1; y1 = v; y[n] = v
        }
        return y
    }
}

func rms(_ x: [Double]) -> Double {
    guard !x.isEmpty else { return 0 }
    return (x.reduce(0) { $0 + $1 * $1 } / Double(x.count)).squareRoot()
}

/// Max 10 ms RMS frame — the same quantity LocalAnalyzer gates with.
func maxFrameRms(_ x: [Double]) -> Double {
    let fl = SR / 100
    var best = 0.0
    var w = 0
    while (w + 1) * fl <= x.count {
        var s = 0.0
        for i in (w * fl)..<((w + 1) * fl) { s += x[i] * x[i] }
        best = max(best, (s / Double(fl)).squareRoot())
        w += 1
    }
    return best
}

func scaled(_ x: [Double], toRms target: Double) -> [Double] {
    let r = rms(x); return r > 0 ? x.map { $0 * target / r } : x
}

/// Pink noise (Paul Kellet's refined filter), unit RMS.
func pinkNoise(_ n: Int, _ g: inout RNG) -> [Double] {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
    var out = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let w = g.gauss()
        b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520; b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.0168980
        out[i] = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
    }
    return scaled(out, toRms: 1)
}

/// Low-frequency rumble (HVAC / traffic / fridge): white → 2× LP 150 Hz, unit RMS.
func rumble(_ n: Int, _ g: inout RNG) -> [Double] {
    var w = [Double](repeating: 0, count: n)
    for i in 0..<n { w[i] = g.gauss() }
    return scaled(Biquad.lowpass(150).apply(Biquad.lowpass(150).apply(w)), toRms: 1)
}

// MARK: - Scenario model

struct Factors {
    /// Melon damping τ 15–120 ms (a knuckle on a real melon is a short,
    /// dull "thonk"). Off: the harness's τ 20–600 ms.
    var realisticDamping = false
    /// Knuckle excitation: broadband contact click (τ 1.5–5 ms) plus a
    /// second, weaker mode at 1.5–2.3 × f0. Off: one pure damped sine.
    var knock = false
    /// Mic + room: pink room noise (−72…−55 dBFS) + low rumble
    /// (−70…−50 dBFS) + mic self-noise (−80 dBFS), then the MEMS
    /// mic's 2nd-order high-pass (60–120 Hz). Off: harness white noise.
    var micAndRoom = false
    /// Thump level as a max-10 ms-RMS in dBFS, uniform −60…−25.
    /// Off: harness peak amplitude 0.003–0.6.
    var realisticLevel = false
    /// 2–4 knocks 0.35–0.9 s apart (people knock a melon more than once
    /// despite the "one good knock" prompt). Off: one knock.
    var multiTap = false
    /// Recording-start touch click (inside the trimmed head) and, with
    /// p = 0.5, one low-frequency handling bump (30–90 Hz) at −6…+6 dB
    /// relative to the knock.
    var handling = false
}

struct Truth {
    let f0: Double
    let tau: Double
    let levelDb: Double
    let taps: Int
    var label: String { f0 < 160 ? "OVERRIPE" : (f0 < 280 ? "RIPE" : "UNRIPE") }
}

/// One knock of the melon starting at `on` (added into `s`).
func addKnock(into s: inout [Double], on: Int, f0: Double, tau: Double, amp: Double,
              f: Factors, mode2: (ratio: Double, amp: Double, tauScale: Double),
              click: (amp: Double, tau: Double), _ g: inout RNG) {
    let n = s.count
    let ph = g.r(0, 0.3)
    let end = min(n, on + Int(Double(SR) * (tau * 8 + 0.05)))
    for i in on..<end {
        let t = Double(i - on) / Double(SR)
        var v = amp * exp(-t / tau) * sin(2 * .pi * f0 * t + ph)
        if f.knock {
            let rise = t < 0.002 ? 0.5 * (1 - cos(.pi * t / 0.002)) : 1   // 2 ms contact rise
            v *= rise
            v += amp * mode2.amp * exp(-t / (tau * mode2.tauScale)) * sin(2 * .pi * f0 * mode2.ratio * t)
            v += amp * click.amp * exp(-t / click.tau) * g.gauss()
        }
        s[i] += v
    }
}

func makeSignal(_ f: Factors, _ g: inout RNG) -> (samples: [Double], truth: Truth) {
    let n = Int(Double(SR) * SECONDS)
    // Melon. 70 % of cases in the 160–280 Hz RIPE band (task brief),
    // 15 % below, 15 % above.
    let pick = g.u()
    let f0 = pick < 0.7 ? g.r(160, 280) : (pick < 0.85 ? g.r(110, 160) : g.r(280, 340))
    let tau = f.realisticDamping ? exp(g.r(log(0.015), log(0.120))) : g.r(0.02, 0.6)
    let mode2 = (ratio: g.r(1.5, 2.3), amp: g.r(0.2, 0.6), tauScale: g.r(0.4, 0.8))
    let click = (amp: g.r(0.5, 2.0), tau: g.r(0.0015, 0.005))

    // Knock schedule.
    let first = g.r(0.5, 2.5)
    var onsets = [first]
    if f.multiTap {
        let count = g.i(2, 4)
        while onsets.count < count { onsets.append(onsets.last! + g.r(0.35, 0.9)) }
        onsets = onsets.filter { $0 < SECONDS - 0.4 }
    }

    // Acoustic knock track (unit amplitude first, scaled later).
    var knock = [Double](repeating: 0, count: n)
    for (k, t0) in onsets.enumerated() {
        let jitter = k == 0 ? 1.0 : undb(g.r(-4, 4))
        let fj = f0 * (k == 0 ? 1 : g.r(0.98, 1.02))
        addKnock(into: &knock, on: Int(t0 * Double(SR)), f0: fj, tau: tau, amp: jitter,
                 f: f, mode2: mode2, click: click, &g)
    }

    var hpf: Biquad? = nil
    if f.micAndRoom { hpf = Biquad.highpass(g.r(60, 120)) }
    func mic(_ x: [Double]) -> [Double] { hpf?.apply(x) ?? x }

    // Level: set where the mic delivers it.
    let levelDb: Double
    if f.realisticLevel {
        levelDb = g.r(-60, -25)
        let measured = maxFrameRms(mic(knock))
        knock = knock.map { $0 * undb(levelDb) / measured }
    } else {
        let amp = g.r(0.003, 0.6)          // harness: peak amplitude
        let pk = knock.map(abs).max() ?? 1
        knock = knock.map { $0 * amp / pk }
        levelDb = db(maxFrameRms(mic(knock)))
    }

    var acoustic = knock
    if f.handling {
        // Finger lifting off the record button (lands in the 0.3 s trimmed head).
        let at = Int(g.r(0.0, 0.15) * Double(SR))
        let a = undb(levelDb) * g.r(0.5, 3)
        for i in at..<min(n, at + SR / 200) { acoustic[i] += a * g.gauss() * exp(-Double(i - at) / Double(SR) / 0.002) }
        if g.u() < 0.5 {
            let bt = g.r(0.4, SECONDS - 0.4), bf = g.r(30, 90), ba = undb(levelDb + g.r(-6, 6)) * 1.4
            let on = Int(bt * Double(SR))
            for i in on..<min(n, on + SR / 5) {
                let t = Double(i - on) / Double(SR)
                acoustic[i] += ba * exp(-t / 0.03) * sin(2 * .pi * bf * t)
            }
        }
    }
    if f.micAndRoom {
        let pink = pinkNoise(n, &g), rum = rumble(n, &g)
        let pl = undb(g.r(-72, -55)), rl = undb(g.r(-70, -50))
        for i in 0..<n { acoustic[i] += pl * pink[i] + rl * rum[i] }
    }
    var out = mic(acoustic)
    if f.micAndRoom {
        for i in 0..<n { out[i] += undb(-80) * g.gauss() }
    } else {
        let wn = g.r(0.0001, 0.004)        // harness: uniform white noise
        for i in 0..<n { out[i] += wn * g.r(-1, 1) }
    }
    return (out, Truth(f0: f0, tau: tau, levelDb: levelDb, taps: onsets.count))
}

// MARK: - Running + tallying

struct Outcome {
    let truth: Truth
    let verdict: String
    let gate: String       // "pass" or the first gate that rejected
    let crest: Double?     // parsed from the debug line when present
    let prom: Double?
    let snr: Double?
}

func gateName(_ debug: String?) -> String {
    guard let d = debug else { return "?" }
    if d.hasSuffix("✓") { return "pass" }
    guard let r = d.range(of: "✗") else { return d == "flat" ? "flat" : "?" }
    let tail = String(d[r.upperBound...])
    if tail.hasPrefix("dec sustained") { return "dec-sustained" }
    if tail.hasPrefix("prom") { return "prom" }
    return String(tail.split(separator: " ").first ?? "?")
}

func parse(_ key: String, _ debug: String?) -> Double? {
    guard let d = debug, let r = d.range(of: key + " ") else { return nil }
    let num = d[r.upperBound...].prefix { "-0123456789.".contains($0) }
    return Double(num)
}

func run(_ samples: [Double], _ truth: Truth, _ p: HeuristicBandsParameters) -> Outcome {
    let res = try! LocalAnalyzer.analyze(samples: samples, sampleRate: SR, parameters: p, modelLabel: "baby-1.0/1.0")
    return Outcome(truth: truth, verdict: res.verdict, gate: gateName(res.debugSummary),
                   crest: parse("crest", res.debugSummary), prom: parse("prom", res.debugSummary),
                   snr: parse("snr", res.debugSummary))
}

func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "  -  " : String(format: "%5.1f%%", 100 * Double(a) / Double(b)) }
func median(_ x: [Double]) -> Double? {
    guard !x.isEmpty else { return nil }
    let s = x.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}
func fmt(_ x: Double?) -> String { x.map { String(format: "%5.1f", $0) } ?? "  -  " }

struct Tally {
    var outs: [Outcome] = []
    var n: Int { outs.count }
    var detected: Int { outs.filter { $0.verdict != "UNKNOWN" }.count }
    var correct: Int { outs.filter { $0.verdict == $0.truth.label }.count }
    var gates: [(String, Int)] {
        Dictionary(grouping: outs.filter { $0.gate != "pass" }, by: { $0.gate })
            .map { ($0.key, $0.value.count) }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }
    var verdicts: String {
        ["RIPE", "OVERRIPE", "UNRIPE", "UNKNOWN"].map { v in "\(v.prefix(4)) \(outs.filter { $0.verdict == v }.count)" }.joined(separator: " ")
    }
    func line(_ name: String) -> String {
        let g = gates.prefix(4).map { "\($0.0) \(pct($0.1, n).trimmingCharacters(in: .whitespaces))" }.joined(separator: ", ")
        return "| \(name) | \(n) | \(pct(detected, n)) | \(pct(correct, n)) | \(verdicts) | \(fmt(median(outs.compactMap { $0.crest }))) | \(g.isEmpty ? "—" : g) |"
    }
}

let tableHead = "| scenario | N | detected (non-UNKNOWN) | correct verdict | verdicts | median crest dB | top rejecting gates (share of N) |\n|---|---|---|---|---|---|---|"

func scenario(_ f: Factors, n: Int, seed: UInt64, p: HeuristicBandsParameters = .babyV22) -> Tally {
    var g = RNG(seed: seed)
    var t = Tally()
    for _ in 0..<n {
        let (s, truth) = makeSignal(f, &g)
        t.outs.append(run(s, truth, p))
    }
    return t
}

// MARK: - Modes

var args = Array(CommandLine.arguments.dropFirst())

if args.first == "--wav" {
    // Real recordings → Baby 1.0, with the gate debug line.
    for path in args.dropFirst() {
        do {
            let r = try LocalAnalyzer.analyze(audioURL: URL(fileURLWithPath: path), parameters: .babyV22, modelLabel: "baby-1.0/1.0")
            print("\(path): \(r.verdict) f=\(r.dominantFrequencyHz) | \(r.debugSummary ?? "")")
        } catch { print("\(path): ERROR \(error)") }
    }
    exit(0)
}

var dumpDir: String?
if let i = args.firstIndex(of: "--dump"), i + 1 < args.count { dumpDir = args[i + 1]; args.removeSubrange(i...(i + 1)) }
let N = Int(args.first ?? "") ?? 300

func writeWav(_ s: [Double], to path: String) {
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SR), channels: 1, interleaved: false)!
    let file = try! AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: fmt.settings)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count))!
    buf.frameLength = AVAudioFrameCount(s.count)
    for i in 0..<s.count { buf.floatChannelData![0][i] = Float(s[i]) }
    try! file.write(from: buf)
}

let clean = Factors()
var damp = clean; damp.realisticDamping = true
var knock = clean; knock.knock = true
var room = clean; room.micAndRoom = true
var level = clean; level.realisticLevel = true
var multi = clean; multi.multiTap = true
var hand = clean; hand.handling = true
var r1 = damp; r1.knock = true
var r2 = r1; r2.micAndRoom = true
var r3 = r2; r3.realisticLevel = true
var r4 = r3; r4.multiTap = true
var r5 = r4; r5.handling = true

let scenarios: [(String, Factors)] = [
    ("A0 clean (600-case harness style)", clean),
    ("A1 clean + realistic damping τ15–120ms", damp),
    ("A2 clean + knuckle excitation", knock),
    ("A3 clean + mic HPF & room noise", room),
    ("A4 clean + realistic level −60…−25 dBFS", level),
    ("A5 clean + 2–4 knocks", multi),
    ("A6 clean + handling", hand),
    ("B1 damping + knuckle", r1),
    ("B2 B1 + mic & room", r2),
    ("B3 B2 + level  = phone, 1 knock", r3),
    ("B4 B3 + 2–4 knocks", r4),
    ("B5 B4 + handling = phone, full", r5),
]

print("# MelonThump recognition diagnosis — production LocalAnalyzer, Baby 1.0 (heuristic v2.2)")
print("sample rate \(SR) Hz, \(Int(SECONDS)) s clips (default Listening Duration), N=\(N) per scenario, fixed seeds\n")
print("## 1. Scenario ladder\n")
print(tableHead)
var tallies: [String: Tally] = [:]
for (k, (name, f)) in scenarios.enumerated() {
    let t = scenario(f, n: N, seed: 1000 + UInt64(k))
    tallies[name] = t
    print(t.line(name))
    if let dir = dumpDir {
        var g = RNG(seed: 1000 + UInt64(k))
        let (s, truth) = makeSignal(f, &g)
        let file = "\(dir)/\(name.prefix(2))-f\(Int(truth.f0))-tau\(Int(truth.tau * 1000))ms-\(Int(truth.levelDb))dBFS.wav"
        writeWav(s, to: file)
    }
}

// Breakdowns on the realistic single-knock group B3 (and full B5).
func breakdown(_ title: String, _ t: Tally, bins: [(String, (Outcome) -> Bool)]) {
    print("\n### \(title)\n")
    print("| bin | N | detected | correct | top rejecting gates |\n|---|---|---|---|---|")
    for (label, pred) in bins {
        var sub = Tally(); sub.outs = t.outs.filter(pred)
        let g = sub.gates.prefix(3).map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        print("| \(label) | \(sub.n) | \(pct(sub.detected, sub.n)) | \(pct(sub.correct, sub.n)) | \(g.isEmpty ? "—" : g) |")
    }
}

// Bigger sample for the breakdowns.
let bigB3 = scenario(r3, n: N * 3, seed: 77)
let bigB5 = scenario(r5, n: N * 3, seed: 78)
print("\n## 2. Breakdowns (B3 phone/1 knock, N=\(bigB3.n); B5 phone/full, N=\(bigB5.n))")
breakdown("B3 by knock level (max 10 ms RMS, dBFS; absoluteFloor 0.0056 = −45.0 dBFS)", bigB3, bins: [
    ("−60…−50", { $0.truth.levelDb < -50 }), ("−50…−45", { $0.truth.levelDb >= -50 && $0.truth.levelDb < -45 }),
    ("−45…−40", { $0.truth.levelDb >= -45 && $0.truth.levelDb < -40 }), ("−40…−35", { $0.truth.levelDb >= -40 && $0.truth.levelDb < -35 }),
    ("−35…−25", { $0.truth.levelDb >= -35 }),
])
let loud: (Outcome) -> Bool = { $0.truth.levelDb >= -40 }
breakdown("B3 by damping τ (only knocks ≥ −40 dBFS, so the level gate is out of the picture)", bigB3, bins: [
    ("τ 15–25 ms", { loud($0) && $0.truth.tau < 0.025 }), ("τ 25–40 ms", { loud($0) && $0.truth.tau >= 0.025 && $0.truth.tau < 0.040 }),
    ("τ 40–70 ms", { loud($0) && $0.truth.tau >= 0.040 && $0.truth.tau < 0.070 }), ("τ 70–120 ms", { loud($0) && $0.truth.tau >= 0.070 }),
])
breakdown("B3 by melon band (all levels)", bigB3, bins: [
    ("f0 110–160 (OVERRIPE)", { $0.truth.f0 < 160 }), ("f0 160–280 (RIPE)", { $0.truth.f0 >= 160 && $0.truth.f0 < 280 }),
    ("f0 280–340 (UNRIPE)", { $0.truth.f0 >= 280 }),
])
// Knock count: B3 (1 knock) merged with B4 (2–4 knocks, otherwise identical).
var b3b4 = bigB3
b3b4.outs += scenario(r4, n: N * 3, seed: 79).outs
breakdown("B3 + B4 by number of knocks (only knocks ≥ −40 dBFS)", b3b4, bins: [
    ("1 knock", { loud($0) && $0.truth.taps == 1 }), ("2 knocks", { loud($0) && $0.truth.taps == 2 }),
    ("3–4 knocks", { loud($0) && $0.truth.taps >= 3 }),
])

// Gate knockout: one gate disabled at a time (sensitivity probe only).
func knockout(_ name: String, _ f: (inout HeuristicBandsParameters) -> Void) -> (String, HeuristicBandsParameters) {
    var p = HeuristicBandsParameters.babyV22; f(&p); return (name, p)
}
let knockouts: [(String, HeuristicBandsParameters)] = [
    ("none (Baby 1.0 as shipped)", .babyV22),
    knockout("absfloor off") { $0.absoluteFloor = 0 },
    knockout("width off") { $0.peakWidthMinFrames = 1 },
    knockout("prominence off") { $0.prominenceDbMin = -1000 },
    knockout("attack off") { $0.attackMaxMs = 1e9 },
    knockout("decay off") { $0.decayMaxMs = 1e9; $0.sustainedEndLevelRatio = 1 },
    knockout("crest off") { $0.crestDbMin = -1000; $0.ringTolerance = 1e9 },
    knockout("snr off") { $0.snrDbMin = -1000 },
    knockout("ring off") { $0.ringTolerance = 1e9 },
    knockout("absfloor + crest off") { $0.absoluteFloor = 0; $0.crestDbMin = -1000; $0.ringTolerance = 1e9 },
    knockout("absfloor + crest + snr off") { $0.absoluteFloor = 0; $0.crestDbMin = -1000; $0.ringTolerance = 1e9; $0.snrDbMin = -1000 },
    // Fix-direction probes (measurement only, not proposals):
    knockout("probe: absfloor 0.002 (−54 dBFS)") { $0.absoluteFloor = 0.002 },
    knockout("probe: FFT segment 150 ms") { $0.segmentMs = 150 },
    knockout("probe: absfloor 0.002 + segment 150 ms") { $0.absoluteFloor = 0.002; $0.segmentMs = 150 },
]
print("\n## 3. Gate knockout (one gate disabled at a time; same signals)\n")
print("| disabled | B3 detected | B3 correct | B5 detected | B5 correct | A0 clean detected | B3 silence false-positive |\n|---|---|---|---|---|---|---|")
// Silence control under the phone channel (room noise, rumble, mic
// self-noise, HPF, and in half the clips a handling bump at −50…−30
// dBFS — no knock at all). A knockout that "fixes" detection by also
// passing empty rooms is not a fix.
func silenceFP(_ p: HeuristicBandsParameters) -> String {
    var g = RNG(seed: 99)
    let n = Int(Double(SR) * SECONDS)
    let none = Truth(f0: 0, tau: 0, levelDb: -200, taps: 0)
    var fp = 0
    for _ in 0..<N {
        var room = [Double](repeating: 0, count: n)
        let pink = pinkNoise(n, &g), rum = rumble(n, &g)
        let pl = undb(g.r(-72, -55)), rl = undb(g.r(-70, -50))
        for i in 0..<n { room[i] = pl * pink[i] + rl * rum[i] }
        if g.u() < 0.5 {
            let on = Int(g.r(0.4, SECONDS - 0.4) * Double(SR)), bf = g.r(30, 90), ba = undb(g.r(-50, -30)) * 1.4
            for i in on..<min(n, on + SR / 5) {
                let t = Double(i - on) / Double(SR); room[i] += ba * exp(-t / 0.03) * sin(2 * .pi * bf * t)
            }
        }
        room = Biquad.highpass(g.r(60, 120)).apply(room)
        for i in 0..<n { room[i] += undb(-80) * g.gauss() }
        if run(room, none, p).verdict != "UNKNOWN" { fp += 1 }
    }
    return pct(fp, N)
}
let a0Small = N
for (name, p) in knockouts {
    let b3 = scenario(r3, n: N, seed: 1009, p: p)
    let b5 = scenario(r5, n: N, seed: 1011, p: p)
    let a0 = scenario(clean, n: a0Small, seed: 1000, p: p)
    print("| \(name) | \(pct(b3.detected, b3.n)) | \(pct(b3.correct, b3.n)) | \(pct(b5.detected, b5.n)) | \(pct(b5.correct, b5.n)) | \(pct(a0.detected, a0.n)) | \(silenceFP(p)) |")
}

// Measured gate values on the phone group, loud knocks only.
let loudB3 = bigB3.outs.filter(loud)
print("\n## 4. Gate values measured on B3 knocks ≥ −40 dBFS (N=\(loudB3.count))\n")
func q(_ x: [Double], _ p: Double) -> String { x.isEmpty ? "-" : String(format: "%.1f", x.sorted()[min(x.count - 1, Int(Double(x.count) * p))]) }
let crests = loudB3.compactMap { $0.crest }, proms = loudB3.compactMap { $0.prom }, snrs = loudB3.compactMap { $0.snr }
print("| value | gate | n | p10 | p50 | p90 |\n|---|---|---|---|---|---|")
print("| local crest dB | ≥ 18 | \(crests.count) | \(q(crests, 0.1)) | \(q(crests, 0.5)) | \(q(crests, 0.9)) |")
print("| prominence dB | ≥ 10 | \(proms.count) | \(q(proms, 0.1)) | \(q(proms, 0.5)) | \(q(proms, 0.9)) |")
print("| spectral SNR dB | ≥ 6 | \(snrs.count) | \(q(snrs, 0.1)) | \(q(snrs, 0.5)) | \(q(snrs, 0.9)) |")
let a0crest = tallies["A0 clean (600-case harness style)"]!.outs.compactMap { $0.crest }
print("| local crest dB, A0 clean | ≥ 18 | \(a0crest.count) | \(q(a0crest, 0.1)) | \(q(a0crest, 0.5)) | \(q(a0crest, 0.9)) |")
