import AVFoundation
import Foundation

/// On-device tap analysis, heuristic-v2.
///
/// v1 took the loudest spectral peak of the whole clip — with no
/// thump at all it happily classified background noise, and the
/// verdict swung from run to run. v2 first proves a credible thump
/// happened, using time-domain gates on the 10 ms RMS envelope:
///
///   prominence — the peak must tower ≥ 10 dB over the median
///                envelope (the noise floor). Room noise sits within
///                ~1–6 dB of its own median; a knock next to the
///                phone is 15–30 dB over.
///   attack     — the envelope must rise from half-peak to peak in
///                ≤ 80 ms (a knock is a transient; swells and
///                crescendos are not).
///   decay      — after the peak the envelope must fall to 1/e
///                within ≤ 800 ms (a thump rings down; hums and
///                sustained tones do not).
///
/// Only then is frequency measured — on the 500 ms segment starting
/// at the thump, in the 60–600 Hz band where melon fundamentals
/// live — and cross-checked against a noise-only segment's spectrum
/// (peak must stand ≥ 6 dB over it). Any failure returns UNKNOWN
/// ("no clear thump heard") instead of a made-up verdict.
/// Thresholds validated on synthetic signals (noise-only → UNKNOWN;
/// damped bursts at 140/200/320 Hz → correct verdicts).
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
                modelVersion: "heuristic-v2")
        }
        let verdict = classify(dominantHz: features.dominantHz)
        return TapResult(
            dominantFrequencyHz: round2(features.dominantHz),
            spectralCentroidHz: round2(features.centroidHz),
            decayTimeMs: round2(features.decayMs),
            verdict: verdict.verdict,
            confidence: round2(verdict.confidence),
            modelVersion: "heuristic-v2")
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
    }

    private static func extractFeatures(samples: [Double], sampleRate: Int) throws -> Features {
        let frameLen = max(16, sampleRate / 100)  // 10 ms envelope frames
        let frameCount = samples.count / frameLen
        guard frameCount >= 2 else { throw AnalyzerError.tooShort }

        // RMS envelope.
        var env = [Double](repeating: 0, count: frameCount)
        var peak = 0.0
        var peakIdx = 0
        for w in 0..<frameCount {
            var sum = 0.0
            let base = w * frameLen
            for i in 0..<frameLen {
                let s = samples[base + i]
                sum += s * s
            }
            env[w] = (sum / Double(frameLen)).squareRoot()
            if env[w] > peak {
                peak = env[w]
                peakIdx = w
            }
        }
        let frameMs = 1000.0 * Double(frameLen) / Double(sampleRate)
        let noThump = Features(heardThump: false, dominantHz: 0, centroidHz: 0, decayMs: 0)
        guard peak > 0 else { return noThump }

        // Decay (shared by the gate and the reported feature): first
        // frame after the peak at or below peak/e.
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
        var rejected = Features(heardThump: false, dominantHz: 0, centroidHz: 0, decayMs: decayMs)

        // Gate 1 — prominence over the noise floor (median envelope).
        let floor = median(env)
        guard floor > 0, 20 * log10(peak / floor) >= prominenceDbMin else { return rejected }

        // Gate 2 — attack: rise from half-peak to peak must be fast.
        // (Skipped when the peak lands in the first frames: nothing
        // before it to measure.)
        if peakIdx >= 3 {
            var j = peakIdx
            while j > 0, env[j - 1] > peak * 0.5 { j -= 1 }
            guard Double(peakIdx - j) * frameMs <= attackMaxMs else { return rejected }
        }

        // Gate 3 — decay: a thump rings down promptly. Unverifiable
        // when the recording ends first (thump at the very end).
        if decayVerified {
            guard decayMs <= decayMaxMs else { return rejected }
        }

        // Frequency: FFT of the 500 ms segment starting just before
        // the thump, peak within the melon band.
        let onsetSec = Double(peakIdx * frameLen) / Double(sampleRate)
        let segStart = max(0, Int((onsetSec - 0.03) * Double(sampleRate)))
        guard let signalSpectrum = spectrum(samples: samples, start: segStart, sampleRate: sampleRate) else {
            return rejected
        }
        let binHz = Double(sampleRate) / Double(signalSpectrum.count * 2)
        var peakMag = 0.0
        var peakBin = 0
        var weightedSum = 0.0
        var magSum = 0.0
        for k in 1..<signalSpectrum.count {
            let freq = Double(k) * binHz
            guard bandHz.contains(freq) else { continue }
            let mag = signalSpectrum[k]
            weightedSum += freq * mag
            magSum += mag
            if mag > peakMag {
                peakMag = mag
                peakBin = k
            }
        }
        guard peakMag > 0 else { return rejected }
        let dominantHz = Double(peakBin) * binHz

        // Spectral SNR: the peak must stand over a noise-only
        // segment's spectrum (same FFT size). Prefer a segment well
        // after the thump; fall back to one before it. Skipped when
        // no clean segment exists — the time gates already passed.
        if let noiseStart = noiseSegmentStart(onsetSec: onsetSec, totalSec: Double(samples.count) / Double(sampleRate), sampleRate: sampleRate),
           let noiseSpectrum = spectrum(samples: samples, start: noiseStart, sampleRate: sampleRate),
           noiseSpectrum.count == signalSpectrum.count {
            let bandMags = (1..<noiseSpectrum.count).filter { bandHz.contains(Double($0) * binHz) }.map { noiseSpectrum[$0] }
            if !bandMags.isEmpty {
                let ref = max(noiseSpectrum[peakBin], median(bandMags))
                if ref > 0, 20 * log10(peakMag / ref) < snrDbMin {
                    return rejected
                }
            }
        }

        rejected = Features(
            heardThump: true,
            dominantHz: dominantHz,
            centroidHz: magSum > 0 ? weightedSum / magSum : 0,
            decayMs: decayMs)
        return rejected
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

    /// Hann-windowed, zero-padded FFT magnitudes (first half) of the
    /// 500 ms segment starting at `start`; nil if too short.
    private static func spectrum(samples: [Double], start: Int, sampleRate: Int) -> [Double]? {
        let count = Int(segmentMs / 1000.0 * Double(sampleRate))
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
