import AVFoundation
import Foundation

/// On-device tap analysis — the feature extraction and classifier are a
/// faithful Swift port of the server's v1 pipeline (AudioFeatureExtractor
/// + HeuristicRipenessModel): up to the first 2 s → Hann window → FFT →
/// dominant frequency (50–4000 Hz band), spectral centroid, RMS-envelope
/// decay → fixed thresholds (<160 overripe / 160–280 ripe / >280 unripe).
/// The recording itself is decoded with AVAudioFile, which natively
/// handles every WAV variant AVAudioRecorder produces — a hand-rolled
/// header parser kept rejecting real-device recordings.
/// The server no longer analyzes audio; it only serves the client
/// version policy.
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

    static func analyze(audioURL: URL) throws -> TapResult {
        let (samples, sampleRate) = try loadSamples(url: audioURL)
        let features = try extractFeatures(samples: samples, sampleRate: sampleRate)
        let verdict = classify(dominantHz: features.dominantHz)
        return TapResult(
            dominantFrequencyHz: round2(features.dominantHz),
            spectralCentroidHz: round2(features.centroidHz),
            decayTimeMs: round2(features.decayMs),
            verdict: verdict.verdict,
            confidence: round2(verdict.confidence),
            modelVersion: "heuristic-v1")
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
        let dominantHz: Double
        let centroidHz: Double
        let decayMs: Double
    }

    private static func extractFeatures(samples: [Double], sampleRate: Int) throws -> Features {
        let minFreqHz = 50.0
        let maxFreqHz = 4000.0
        let n = min(samples.count, 2 * sampleRate)
        guard n >= 256 else { throw AnalyzerError.tooShort }

        var size = 1
        while size < n { size <<= 1 }

        var windowed = [Double](repeating: 0, count: size)
        for i in 0..<n {
            let hann = 0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n - 1)))
            windowed[i] = samples[i] * hann
        }

        let spectrum = fftMagnitudes(windowed)
        let bins = size / 2
        let binHz = Double(sampleRate) / Double(size)

        var maxMag = 0.0
        var maxBin = 0
        var weightedSum = 0.0
        var magSum = 0.0
        for k in 1..<bins {
            let freq = Double(k) * binHz
            if freq < minFreqHz || freq > maxFreqHz { continue }
            let mag = spectrum[k]
            weightedSum += freq * mag
            magSum += mag
            if mag > maxMag {
                maxMag = mag
                maxBin = k
            }
        }

        return Features(
            dominantHz: Double(maxBin) * binHz,
            centroidHz: magSum > 0 ? weightedSum / magSum : 0,
            decayMs: decayTimeMs(samples: samples, sampleRate: sampleRate))
    }

    /// Time from the envelope peak until it first drops to 1/e of the peak.
    /// Envelope = RMS over 20 ms windows.
    private static func decayTimeMs(samples: [Double], sampleRate: Int) -> Double {
        let window = max(16, sampleRate / 50)
        let windows = samples.count / window
        guard windows >= 2 else { return 0 }

        var env = [Double](repeating: 0, count: windows)
        var peak = 0.0
        var peakIdx = 0
        for w in 0..<windows {
            var sum = 0.0
            for i in 0..<window {
                let s = samples[w * window + i]
                sum += s * s
            }
            env[w] = (sum / Double(window)).squareRoot()
            if env[w] > peak {
                peak = env[w]
                peakIdx = w
            }
        }
        guard peak > 0 else { return 0 }
        let target = peak / 2.718281828459045  // 1/e of peak, as in the Java original (Math.E)
        for w in (peakIdx + 1)..<windows {
            if env[w] <= target {
                return 1000.0 * Double(w - peakIdx) * Double(window) / Double(sampleRate)
            }
        }
        return 1000.0 * Double(windows - 1 - peakIdx) * Double(window) / Double(sampleRate)
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
