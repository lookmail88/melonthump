import AVFoundation
import Foundation

/// On-device tap analysis, heuristic-v2.2.
///
/// v1 took the loudest spectral peak of the whole clip — with no
/// thump at all it happily classified background noise, and the
/// verdict swung from run to run. v2 first proves a credible thump
/// happened, using time-domain gates on the 10 ms RMS envelope
/// (prominence ≥ 10 dB over the median floor, attack ≤ 80 ms,
/// decay to 1/e ≤ 800 ms), then measures frequency only on the
/// 500 ms segment at the thump, in the 60–600 Hz melon band,
/// cross-checked against a noise segment's spectrum (≥ 6 dB).
///
/// v2.1 (silent rooms still occasionally read OVERRIPE): low-
/// frequency environmental transients pass the envelope gates, so
/// spectral gates were added — local crest ≥ 18 dB over the peak's
/// 15–75 Hz neighbourhood (a resonance is one sharp line; a
/// broadband desk knock is a smooth hump at ≈10–12 dB), ring pitch
/// consistency within 15%, and a tightened decay exemption (a sound
/// still loud when the recording ends is sustained, not a thump).
///
/// v2.2 (field test of v2: 4 of 5 silent recordings still read
/// OVERRIPE — a fixed low-frequency event in the room kept passing,
/// most plausibly recording-start / handling transients, which the
/// attack gate even exempted at the clip head):
///   usable window — the peak is searched only between 0.3 s and
///     (end − 0.2 s); start pops and set-down bumps at the edges
///     are out of the game entirely.
///   peak width — the envelope must hold ≥ half-peak for at least
///     2 frames (~20 ms); single-frame digital clicks are not
///     knocks.
///   absolute floor — a peak under ≈ −45 dBFS is room micro-noise
///     no matter how far it towers over an even quieter floor.
/// And every result now carries a debug summary of the gate values
/// (shown on the result screen) so a false verdict can be traced
/// to the exact gate that leaked. Validated on synthetic signals
/// (Python mirror, 16 cases): all noise / pop / click / broadband-
/// knock cases → UNKNOWN; damped bursts at 140/200/320 Hz, even
/// weak ones, → correct verdicts. Honest limit: a genuinely
/// resonant low knock (a hollow door at ~95 Hz) is physically
/// indistinguishable from an overripe melon.
///
/// The recording itself is decoded with AVAudioFile, which natively
/// handles every WAV variant the recorder produces. The server no
/// longer analyzes audio; it only serves the client version policy.
enum LocalAnalyzer {

    enum AnalyzerError: Error, LocalizedError {
        case unreadableRecording
        case tooShort

        var errorDescription: String? {
            switch self {
            case .unreadableRecording: return "Could not read the recording."
            case .tooShort: return "Recording is too short — thump once more."
            }
        }
    }

    // Gate / band constants (see header).
    private static let prominenceDbMin = 10.0
    private static let attackMaxMs = 80.0
    private static let decayMaxMs = 800.0
    private static let bandHz = 60.0...600.0
    private static let snrDbMin = 6.0
    private static let crestDbMin = 18.0
    private static let ringTolerance = 0.15
    private static let absoluteFloor = 0.0056  // ≈ −45 dBFS
    private static let trimHeadMs = 300.0
    private static let trimTailMs = 200.0
    private static let segmentMs = 500.0

    static func analyze(audioURL: URL) throws -> TapResult {
        let (samples, sampleRate) = try loadSamples(url: audioURL)
        let features = try extractFeatures(samples: samples, sampleRate: sampleRate)
        guard features.heardThump else {
            return TapResult(
                dominantFrequencyHz: 0,
                spectralCentroidHz: 0,
                decayTimeMs: round2(features.decayMs),
                verdict: "UNKNOWN",
                confidence: 0.3,
                modelVersion: "heuristic-v2.2",
                debugSummary: features.debug)
        }
        let verdict = classify(dominantHz: features.dominantHz)
        return TapResult(
            dominantFrequencyHz: round2(features.dominantHz),
            spectralCentroidHz: round2(features.centroidHz),
            decayTimeMs: round2(features.decayMs),
            verdict: verdict.verdict,
            confidence: round2(verdict.confidence),
            modelVersion: "heuristic-v2.2",
            debugSummary: features.debug)
    }

    // MARK: - Recording decoding (AVAudioFile; channels mixed to mono)

    private static func loadSamples(url: URL) throws -> (samples: [Double], sampleRateHz: Int) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AnalyzerError.unreadableRecording
        }
        let format = file.processingFormat
        let capacity = AVAudioFrameCount(file.length)
        guard capacity > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AnalyzerError.tooShort
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw AnalyzerError.unreadableRecording
        }
        guard let channelData = buffer.floatChannelData else {
            throw AnalyzerError.unreadableRecording
        }
        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        var samples = [Double](repeating: 0, count: frames)
        for i in 0..<frames {
            var acc = 0.0
            for c in 0..<channels {
                acc += Double(channelData[c][i])
            }
            samples[i] = acc / Double(channels)
        }
        return (samples, Int(format.sampleRate))
    }

    // MARK: - Feature extraction

    private struct Features {
        let heardThump: Bool
        let dominantHz: Double
        let centroidHz: Double
        let decayMs: Double
        let debug: String
    }

    private static func extractFeatures(samples: [Double], sampleRate: Int) throws -> Features {
        let frameLen = max(16, sampleRate / 100)  // 10 ms envelope frames
        let frameCount = samples.count / frameLen
        guard frameCount >= 2 else { throw AnalyzerError.tooShort }
        let frameMs = 1000.0 * Double(frameLen) / Double(sampleRate)

        // RMS envelope.
        var env = [Double](repeating: 0, count: frameCount)
        for w in 0..<frameCount {
            var sum = 0.0
            let base = w * frameLen
            for i in 0..<frameLen {
                let s = samples[base + i]
                sum += s * s
            }
            env[w] = (sum / Double(frameLen)).squareRoot()
        }

        // Usable window: head/tail trimmed (see header). The peak
        // and the noise floor both come from this window only.
        var lo = Int(trimHeadMs / frameMs)
        var hi = frameCount - Int(trimTailMs / frameMs)
        if hi - lo < 10 { lo = 0; hi = frameCount }
        var peak = 0.0
        var peakIdx = lo
        for w in lo..<hi {
            if env[w] > peak {
                peak = env[w]
                peakIdx = w
            }
        }
        let floor = median(Array(env[lo..<hi]))
        guard peak > 0 else {
            return Features(heardThump: false, dominantHz: 0, centroidHz: 0, decayMs: 0, debug: "flat")
        }
        let onsetSec = Double(peakIdx * frameLen) / Double(sampleRate)

        // Decay (gate + reported feature): first frame after the
        // peak at or below peak/e.
        var decayMs = Double(frameCount - 1 - peakIdx) * frameMs
        var decayVerified = false
        let decayTarget = peak / 2.718281828459045
        for w in (peakIdx + 1)..<frameCount {
            if env[w] <= decayTarget {
                decayMs = Double(w - peakIdx) * frameMs
                decayVerified = true
                break
            }
        }

        // Debug summary, built up as gates pass; a rejection names
        // the gate that failed. For pre-spectrum rejections the
        // would-be frequency/crest are attached (computed once).
        var dbg = String(format: "pk@%.2fs pk %.3f", onsetSec, peak)
        var earlyNote: String?
        func spectrumNote() -> String {
            if let earlyNote { return earlyNote }
            let start = max(0, Int((onsetSec - 0.03) * Double(sampleRate)))
            var note = ""
            if let spec = spectrum(samples: samples, start: start, sampleRate: sampleRate),
               let bp = bandPeak(spectrum: spec, binHz: Double(sampleRate) / Double(spec.count * 2)) {
                note = String(format: " · f≈%.0f crest %.1f", bp.freq, bp.localCrestDb)
            }
            earlyNote = note
            return note
        }
        func reject(_ gate: String) -> Features {
            Features(heardThump: false, dominantHz: 0, centroidHz: 0,
                     decayMs: decayMs, debug: dbg + spectrumNote() + " ✗" + gate)
        }

        // Gate — absolute floor: micro-noise in a silent room.
        guard peak >= absoluteFloor else { return reject("absfloor") }

        // Gate — peak width: single-frame clicks are not knocks.
        var width = 1
        var k = peakIdx - 1
        while k >= 0, env[k] >= peak * 0.5 { width += 1; k -= 1 }
        k = peakIdx + 1
        while k < frameCount, env[k] >= peak * 0.5 { width += 1; k += 1 }
        guard width >= 2 else { return reject("width \(width)f") }
        dbg += " · w \(width)f"

        // Gate 1 — prominence over the noise floor (median envelope).
        guard floor > 0 else { return reject("floor") }
        let promDb = 20 * log10(peak / floor)
        guard promDb >= prominenceDbMin else { return reject(String(format: "prom %.1f", promDb)) }
        dbg += String(format: " · prom %.1f", promDb)

        // Gate 2 — attack: rise from half-peak to peak must be fast.
        // (Skipped when the peak lands in the first frames: nothing
        // before it to measure.)
        if peakIdx >= 3 {
            var j = peakIdx
            while j > 0, env[j - 1] > peak * 0.5 { j -= 1 }
            let attackMs = Double(peakIdx - j) * frameMs
            guard attackMs <= attackMaxMs else { return reject("atk \(Int(attackMs))ms") }
            dbg += " · atk \(Int(attackMs))ms"
        }

        // Gate 3 — decay: a thump rings down promptly. When no 1/e
        // crossing is observed, the end-of-clip exemption is narrow:
        // the clip must end too soon to judge (< decayMaxMs of
        // post-peak audio) AND the level must already be falling —
        // a sound still loud at the end is sustained, not a thump.
        if decayVerified {
            guard decayMs <= decayMaxMs else { return reject("dec \(Int(decayMs))ms") }
        } else {
            let remainingMs = Double(frameCount - 1 - peakIdx) * frameMs
            guard remainingMs < decayMaxMs, env[frameCount - 1] <= 0.6 * peak else {
                return reject("dec sustained")
            }
        }
        dbg += " · dec \(Int(decayMs))ms"

        // Frequency: FFT of the 500 ms segment starting just before
        // the thump, peak within the melon band.
        let segStart = max(0, Int((onsetSec - 0.03) * Double(sampleRate)))
        guard let signalSpectrum = spectrum(samples: samples, start: segStart, sampleRate: sampleRate) else {
            return reject("spec")
        }
        earlyNote = ""  // real values follow; no would-be note needed
        let binHz = Double(sampleRate) / Double(signalSpectrum.count * 2)
        guard let main = bandPeak(spectrum: signalSpectrum, binHz: binHz) else { return reject("peak") }
        let dominantHz = main.freq
        let peakMag = main.mag
        dbg += String(format: " · f %.0f crest %.1f", dominantHz, main.localCrestDb)

        // Gate 4 — local spectral crest: the peak must tower over
        // its own neighbourhood (see header). Broadband knocks fail.
        guard main.localCrestDb >= crestDbMin else { return reject("crest") }

        var weightedSum = 0.0
        var magSum = 0.0
        for k2 in 1..<signalSpectrum.count {
            let freq = Double(k2) * binHz
            guard bandHz.contains(freq) else { continue }
            weightedSum += freq * signalSpectrum[k2]
            magSum += signalSpectrum[k2]
        }

        // Gate 5 — spectral SNR: the peak must stand over a
        // noise-only segment's spectrum (same FFT size). Prefer a
        // segment well after the thump; fall back to one before it.
        // Skipped when no clean segment exists — gates 1–4 passed.
        if let noiseStart = noiseSegmentStart(onsetSec: onsetSec, totalSec: Double(samples.count) / Double(sampleRate), sampleRate: sampleRate),
           let noiseSpectrum = spectrum(samples: samples, start: noiseStart, sampleRate: sampleRate),
           noiseSpectrum.count == signalSpectrum.count {
            let bandMags = (1..<noiseSpectrum.count).filter { bandHz.contains(Double($0) * binHz) }.map { noiseSpectrum[$0] }
            if !bandMags.isEmpty {
                let ref = max(noiseSpectrum[main.bin], median(bandMags))
                if ref > 0 {
                    let snrDb = 20 * log10(peakMag / ref)
                    dbg += String(format: " · snr %.1f", snrDb)
                    guard snrDb >= snrDbMin else { return reject("snr") }
                }
            }
        }

        // Gate 6 — ring pitch consistency: if a clear tone is still
        // audible later in the ring, it must be the same pitch.
        // One-sided: an inaudible ring verifies nothing.
        let ringOffsetSec = max(0.10, decayMs / 1000.0)
        let ringStart = Int((onsetSec + ringOffsetSec) * Double(sampleRate))
        if ringStart + 256 <= samples.count,
           let ringSpectrum = spectrum(samples: samples, start: ringStart, sampleRate: sampleRate, durationMs: 250) {
            let ringBinHz = Double(sampleRate) / Double(ringSpectrum.count * 2)
            if let ring = bandPeak(spectrum: ringSpectrum, binHz: ringBinHz),
               ring.localCrestDb >= crestDbMin {
                dbg += String(format: " · ring %.0f", ring.freq)
                guard abs(ring.freq - dominantHz) / dominantHz <= ringTolerance else {
                    return reject("ring")
                }
            }
        }

        return Features(
            heardThump: true,
            dominantHz: dominantHz,
            centroidHz: magSum > 0 ? weightedSum / magSum : 0,
            decayMs: decayMs,
            debug: dbg + " ✓")
    }

    private struct BandPeak {
        let freq: Double
        let mag: Double
        let bin: Int
        /// Peak height over the median magnitude 15–75 Hz away
        /// within the band, in dB — the resonance sharpness measure.
        let localCrestDb: Double
    }

    /// Strongest in-band peak of a spectrum, with its local crest.
    private static func bandPeak(spectrum: [Double], binHz: Double) -> BandPeak? {
        var peakMag = 0.0
        var peakBin = 0
        for k in 1..<spectrum.count {
            let freq = Double(k) * binHz
            guard bandHz.contains(freq) else { continue }
            if spectrum[k] > peakMag {
                peakMag = spectrum[k]
                peakBin = k
            }
        }
        guard peakMag > 0 else { return nil }
        let freq = Double(peakBin) * binHz
        let neighbours = (1..<spectrum.count).filter { k in
            let f = Double(k) * binHz
            return bandHz.contains(f) && abs(f - freq) >= 15 && abs(f - freq) <= 75
        }.map { spectrum[$0] }
        let ref = neighbours.isEmpty ? 0 : median(neighbours)
        return BandPeak(
            freq: freq,
            mag: peakMag,
            bin: peakBin,
            localCrestDb: ref > 0 ? 20 * log10(peakMag / ref) : 0)
    }

    /// Start sample of a 500 ms noise-only segment: 1.2 s after the
    /// thump if that fits, else the 500 ms ending 0.3 s before it.
    private static func noiseSegmentStart(onsetSec: Double, totalSec: Double, sampleRate: Int) -> Int? {
        let segSec = segmentMs / 1000.0
        if onsetSec + 1.2 + segSec <= totalSec {
            return Int((onsetSec + 1.2) * Double(sampleRate))
        }
        if onsetSec - 0.3 - segSec >= 0 {
            return Int((onsetSec - 0.3 - segSec) * Double(sampleRate))
        }
        return nil
    }

    /// Hann-windowed, zero-padded FFT magnitudes (first half) of
    /// the segment starting at `start`; nil if too short.
    private static func spectrum(samples: [Double], start: Int, sampleRate: Int, durationMs: Double = segmentMs) -> [Double]? {
        let count = Int(durationMs / 1000.0 * Double(sampleRate))
        guard start >= 0, start + 256 <= samples.count else { return nil }
        let available = min(count, samples.count - start)
        var size = 1
        while size < available { size <<= 1 }
        var windowed = [Double](repeating: 0, count: size)
        for i in 0..<available {
            let hann = 0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(available - 1)))
            windowed[i] = samples[start + i] * hann
        }
        let mags = fftMagnitudes(windowed)
        return Array(mags[0..<(size / 2)])
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    // MARK: - Heuristic classifier (placeholder thresholds, as on the server)

    private static func classify(dominantHz f: Double) -> (verdict: String, confidence: Double) {
        let overripeMaxHz = 160.0
        let ripeMaxHz = 280.0
        if f < overripeMaxHz {
            return ("OVERRIPE", confidence(distanceHz: f, scaleHz: overripeMaxHz))
        }
        if f < ripeMaxHz {
            let distToEdge = min(f - overripeMaxHz, ripeMaxHz - f)
            return ("RIPE", confidence(distanceHz: distToEdge, scaleHz: (ripeMaxHz - overripeMaxHz) / 2))
        }
        return ("UNRIPE", confidence(distanceHz: f - ripeMaxHz, scaleHz: 120.0))
    }

    private static func confidence(distanceHz: Double, scaleHz: Double) -> Double {
        let c = 0.55 + 0.40 * min(1.0, distanceHz / scaleHz)
        return min(0.95, c)
    }

    private static func round2(_ v: Double) -> Double {
        (v * 100).rounded() / 100
    }

    // MARK: - Iterative radix-2 FFT (magnitudes only)

    private static func fftMagnitudes(_ input: [Double]) -> [Double] {
        let n = input.count
        var re = input
        var im = [Double](repeating: 0, count: n)

        // Bit-reversal permutation.
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }

        var length = 2
        while length <= n {
            let ang = -2 * Double.pi / Double(length)
            let wRe = cos(ang)
            let wIm = sin(ang)
            let half = length / 2
            for i in stride(from: 0, to: n, by: length) {
                var curRe = 1.0
                var curIm = 0.0
                for k in 0..<half {
                    let a = i + k
                    let b = i + k + half
                    let tRe = re[b] * curRe - im[b] * curIm
                    let tIm = re[b] * curIm + im[b] * curRe
                    re[b] = re[a] - tRe
                    im[b] = im[a] - tIm
                    re[a] += tRe
                    im[a] += tIm
                    let nextRe = curRe * wRe - curIm * wIm
                    curIm = curRe * wIm + curIm * wRe
                    curRe = nextRe
                }
            }
            length <<= 1
        }

        return zip(re, im).map { ($0 * $0 + $1 * $1).squareRoot() }
    }
}
