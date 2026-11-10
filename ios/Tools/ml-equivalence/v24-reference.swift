// FROZEN REFERENCE — heuristic v2.4, do not edit to track production.
//
// This file is a verbatim snapshot of the production analyzer as of
// commit df9dd0d (analyzer v2.4: v2.3 width/crest gates + v2.4
// persistent-spectrum estimator), so ml-equivalence section 4 fails
// the moment production analysis drifts. It freezes:
//   - ios/MelonThump/LocalAnalyzer.swift (whole file), with only
//     `enum LocalAnalyzer` -> `enum LocalAnalyzerV24` and
//     `HeuristicBandsParameters` -> `HeuristicBandsParametersV24`;
//   - from ios/MelonThump/ModelFile.swift, the
//     `HeuristicBandsParameters` stored fields and the
//     `.standard` value set (renamed as above; validation/Codable
//     omitted — the reference never loads files);
//   - the Standard model label "standard/1.0" (modelVersion of every
//     result), via the `analyze(audioURL:)` convenience at the end.
// To deliberately accept a new analyzer, re-freeze from production.

import AVFoundation
import Foundation

/// On-device tap analysis, heuristic-v2.4 (gates parameterised by a model file).
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
///
/// v2.3 (field failure of v2.2: every real-world analysis came back
/// UNKNOWN — prod 17/17, and all 4 captured device recordings were
/// rejected): three gates were calibrated on long synthetic tones
/// and misfire on real knocks, which are short (τ ≈ 10–25 ms),
/// dull and quiet:
///   peak width — a real 10 ms knock is exactly one frame wide on
///     the 10 ms envelope and could never pass; the width is now
///     measured on a 2 ms envelope with the same minimum frame
///     count (≈4 ms above half-peak). Single-sample clicks still
///     fail; real knocks pass.
///   crest rescue — a short burst's own spectral skirt fills the
///     15–75 Hz neighbourhood the crest gate measures against, so
///     its local crest collapses even when it is a clean resonance
///     (a τ=10 ms burst's skirt is only ≈17 dB down 40 Hz away).
///     When the dominant frequency is at or above the overripe
///     boundary (≥ 160 Hz), the same spectrum is re-measured
///     against a wider neighbourhood (40–120 Hz away, outside the
///     skirt) at the same threshold; passing either measurement
///     passes the gate. Broadband events stay broad at any
///     neighbourhood width and still fail. Below 160 Hz nothing
///     is rescued: every silent-room false positive on record is
///     a low-frequency handling transient (30–90 Hz), and that
///     band keeps the strict close-neighbourhood crest.
///   absolute floor — lowered from ≈ −45 to ≈ −54 dBFS; the
///     prominence and crest gates still stand behind it, and the
///     silence control stays at 0 false positives.
///
/// v2.4 (field test of v2.3 on a real melon, 21 knocks: width now
/// passes, but 19/21 still UNKNOWN at the crest/SNR gates, and one
/// knock was confidently misread UNRIPE — a fixed ≈558 Hz contact
/// resonance, present in every session and even in pre-knock
/// handling noise, out-shouted the melon's true ≈213 Hz in the
/// single 500 ms spectrum): the frequency estimator is replaced.
///   persistent spectrum — STFT magnitudes (2048-sample frames,
///     512 hop) averaged over 20–400 ms after the knock peak. The
///     contact component lives in the first ≈25–50 ms; the body
///     resonance persists, so time-averaging separates them (in the
///     clean field sample the 220/560 band-energy ratio runs
///     0.26 → 8.0 → 46.5 across the window).
///   lowest strong peak — the fundamental is the lowest local peak
///     reaching `strongPeakRatio` of the band maximum, at or above
///     `fundamentalMinHz`. The floor is hard: a sub-floor exception
///     was tried and removed the same day (it admitted exactly the
///     low-frequency handling-burst false-positive class, and no
///     field recording ever used it). A louder high component can
///     no longer impersonate the fundamental. Offline on the 29
///     field recordings: the same-melon 21 knocks answer 21/21,
///     all in the RIPE band, median 210 Hz (single-window argmax:
///     8/21, median 559 Hz).
///   spectral gates demoted — crest and SNR are still computed (on
///     the persistent spectrum) and shown in the debug summary, but
///     they now price the confidence instead of rejecting the knock;
///     the ring gate is gone (the persistent spectrum is itself the
///     ring evidence). The time-domain thump gates stay hard: they
///     are what keeps silent rooms at 0 false positives.
///   silence guard — one spectral rejection survives the demotion,
///     because demoting crest outright let 28% of harness silence
///     clips (room noise + handling bumps) through: an event whose
///     persistent-spectrum crest AND time-domain prominence are
///     both weak is not a knock (`flat`). A real knock always
///     clears at least one of the two bars.
///   Estimator tunables live in the model file (the persist* keys);
///   the confidence penalty factors (×0.75 weak crest, ×0.85 weak
///   SNR or clipping) are structural.
/// Validated with the recognition-diagnosis harness (synthetic
/// phone-channel scenarios + the 4 captured device recordings).
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
///
/// 1.2.0 (design doc §1): every tunable now comes from a loaded model
/// (`HeuristicBandsParametersV24`, carried by a `.ml` file — see
/// ModelFile.swift and docs/ml-format.md). Standard's parameters
/// shipped as heuristic v2.2 exactly; the v2.3 gate changes and the
/// v2.4 estimator above are structural and apply on top of the loaded
/// parameters (the estimator's own tunables do live in the file).
/// What stays in code are only structural numerical guards, not
/// tunables: the 16-sample minimum envelope frame, the 256-sample
/// minimum FFT segment, the 3-frame lead an attack needs to be
/// measurable, and e (the decay time is by definition the fall to 1/e).
enum LocalAnalyzerV24 {

    enum AnalyzerError: Error, LocalizedError {
        case unreadableRecording
        case tooShort

        var errorDescription: String? {
            switch self {
            case .unreadableRecording: return L10n.current.t("error.unreadable")
            case .tooShort: return L10n.current.t("error.tooShort")
            }
        }
    }

    // Gate / band values all come from `parameters` (see header).

    static func analyze(audioURL: URL, parameters p: HeuristicBandsParametersV24,
                        modelLabel: String) throws -> TapResult {
        let (samples, sampleRate) = try loadSamples(url: audioURL)
        return try analyze(samples: samples, sampleRate: sampleRate, parameters: p, modelLabel: modelLabel)
    }

    /// Analysis of already-decoded mono samples (the file-free entry
    /// point; also what the v2.2 equivalence harness drives).
    static func analyze(samples: [Double], sampleRate: Int, parameters p: HeuristicBandsParametersV24,
                        modelLabel: String) throws -> TapResult {
        let features = try extractFeatures(samples: samples, sampleRate: sampleRate, p: p)
        guard features.heardThump else {
            return TapResult(
                dominantFrequencyHz: 0,
                spectralCentroidHz: 0,
                decayTimeMs: round2(features.decayMs),
                verdict: "UNKNOWN",
                confidence: p.unknownConfidence,
                modelVersion: modelLabel,
                debugSummary: features.debug)
        }
        let verdict = classify(dominantHz: features.dominantHz, p: p)
        return TapResult(
            dominantFrequencyHz: round2(features.dominantHz),
            spectralCentroidHz: round2(features.centroidHz),
            decayTimeMs: round2(features.decayMs),
            verdict: verdict.verdict,
            confidence: round2(min(p.confidenceMax, verdict.confidence * features.confidenceScale)),
            modelVersion: modelLabel,
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
        /// v2.4: product of the confidence penalties from the
        /// demoted spectral annotations (1 = clean knock).
        var confidenceScale: Double = 1
    }

    private static func extractFeatures(samples: [Double], sampleRate: Int,
                                        p: HeuristicBandsParametersV24) throws -> Features {
        let frameLen = max(16, sampleRate / p.envelopeFramesPerSecond)  // 10 ms envelope frames in v2.2
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
        var lo = Int(p.trimHeadMs / frameMs)
        var hi = frameCount - Int(p.trimTailMs / frameMs)
        if hi - lo < p.minUsableWindowFrames { lo = 0; hi = frameCount }
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
            let start = max(0, Int((onsetSec - p.segmentPrerollMs / 1000.0) * Double(sampleRate)))
            var note = ""
            if let spec = spectrum(samples: samples, start: start, sampleRate: sampleRate, durationMs: p.segmentMs),
               let bp = bandPeak(spectrum: spec, binHz: Double(sampleRate) / Double(spec.count * 2), p: p) {
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
        guard peak >= p.absoluteFloor else { return reject("absfloor") }

        // Gate — peak width: single-frame clicks are not knocks.
        // Measured on a 2 ms envelope (v2.3 — see header): on the
        // 10 ms envelope a real short knock is one frame wide no
        // matter what. The coarse peak's own frame span locates the
        // fine peak; the walk counts fine frames above half-peak.
        let fineLen = max(16, sampleRate / 500)
        let fineCount = samples.count / fineLen
        // The fine envelope is smoothed over 3 frames (6 ms) in
        // the power domain: the raw 2 ms RMS envelope of a low
        // tone (110 Hz period ≈ 9 ms) ripples at 2f0 and would
        // fake a 1-frame width; a burst's edge moves by only
        // ~±2 ms under the same smoothing.
        var finePow = [Double](repeating: 0, count: fineCount)
        for w in 0..<fineCount {
            var sum = 0.0
            let base = w * fineLen
            for i in 0..<fineLen {
                let s = samples[base + i]
                sum += s * s
            }
            finePow[w] = sum / Double(fineLen)
        }
        func fineEnv(_ w: Int) -> Double {
            var acc = 0.0
            var cnt = 0
            for j in (w - 1)...(w + 1) {
                if j >= 0, j < fineCount { acc += finePow[j]; cnt += 1 }
            }
            return (acc / Double(cnt)).squareRoot()
        }
        var finePeak = 0.0
        var fineIdx = 0
        let fineLo = peakIdx * frameLen / fineLen
        let fineHi = min(fineCount, (peakIdx + 1) * frameLen / fineLen)
        for w in fineLo..<fineHi {
            let r = fineEnv(w)
            if r > finePeak { finePeak = r; fineIdx = w }
        }
        var width = 1
        var k = fineIdx - 1
        while k >= 0, fineEnv(k) >= finePeak * p.peakWidthLevelRatio { width += 1; k -= 1 }
        k = fineIdx + 1
        while k < fineCount, fineEnv(k) >= finePeak * p.peakWidthLevelRatio { width += 1; k += 1 }
        guard width >= p.peakWidthMinFrames else { return reject("width \(width)f") }
        dbg += " · w \(width)f"

        // Gate 1 — prominence over the noise floor (median envelope).
        guard floor > 0 else { return reject("floor") }
        let promDb = 20 * log10(peak / floor)
        guard promDb >= p.prominenceDbMin else { return reject(String(format: "prom %.1f", promDb)) }
        dbg += String(format: " · prom %.1f", promDb)

        // Gate 2 — attack: rise from half-peak to peak must be fast.
        // (Skipped when the peak lands in the first frames: nothing
        // before it to measure.)
        if peakIdx >= 3 {
            var j = peakIdx
            while j > 0, env[j - 1] > peak * p.attackLevelRatio { j -= 1 }
            let attackMs = Double(peakIdx - j) * frameMs
            guard attackMs <= p.attackMaxMs else { return reject("atk \(Int(attackMs))ms") }
            dbg += " · atk \(Int(attackMs))ms"
        }

        // Gate 3 — decay: a thump rings down promptly. When no 1/e
        // crossing is observed, the end-of-clip exemption is narrow:
        // the clip must end too soon to judge (< decayMaxMs of
        // post-peak audio) AND the level must already be falling —
        // a sound still loud at the end is sustained, not a thump.
        if decayVerified {
            guard decayMs <= p.decayMaxMs else { return reject("dec \(Int(decayMs))ms") }
        } else {
            let remainingMs = Double(frameCount - 1 - peakIdx) * frameMs
            guard remainingMs < p.decayMaxMs, env[frameCount - 1] <= p.sustainedEndLevelRatio * peak else {
                return reject("dec sustained")
            }
        }
        dbg += " · dec \(Int(decayMs))ms"

        // Frequency (v2.4): persistent-spectrum lowest-strong-peak
        // estimator — see the header for the evidence. The knock's
        // sample-level peak anchors the averaging window.
        var anchor = peakIdx * frameLen
        var anchorVal = 0.0
        let winLo = lo * frameLen
        let winHi = min(samples.count, hi * frameLen)
        for i in winLo..<winHi {
            let v = abs(samples[i])
            if v > anchorVal { anchorVal = v; anchor = i }
        }
        guard let persist = persistentSpectrum(samples: samples, anchorSample: anchor, sampleRate: sampleRate, p: p) else {
            return reject("nofund")
        }
        let avg = persist.mags
        let binHzP = persist.binHz

        // Reference maximum over the estimator band.
        var refMax = 0.0
        var refBin = -1
        for k in 1..<avg.count {
            let f = Double(k) * binHzP
            guard f >= p.bandMinHz, f <= p.persistBandMaxHz else { continue }
            if avg[k] > refMax { refMax = avg[k]; refBin = k }
        }
        guard refMax > 0 else { return reject("nofund") }

        func isLocalMax(_ k: Int) -> Bool {
            avg[k] >= avg[k - 1] && (k + 1 >= avg.count || avg[k] >= avg[k + 1])
        }
        func interpolatedFreq(_ k: Int) -> Double {
            guard k >= 1, k + 1 < avg.count else { return Double(k) * binHzP }
            let a = avg[k - 1], b = avg[k], c = avg[k + 1]
            let denom = a - 2 * b + c
            var d = 0.0
            if denom != 0 { d = max(-0.5, min(0.5, 0.5 * (a - c) / denom)) }
            return (Double(k) + d) * binHzP
        }

        // The fundamental is the lowest strong peak: the contact
        // component can out-shout the body resonance, but it is
        // never the lowest strong line in the persistent spectrum.
        // The scan floor is hard — a sub-floor exception (accept a
        // ≥60% peak below 140 Hz) was tried and removed the same
        // day: every remaining silence false positive (25/300) came
        // through it, all LF handling bursts, and no field recording
        // ever used it. Sub-140 fundamentals stay UNKNOWN until a
        // validation set with real sub-140 melons exists.
        var chosenBin = -1
        let strongBar = p.strongPeakRatio * refMax
        for k in 1..<avg.count {
            let f = Double(k) * binHzP
            guard f >= p.fundamentalMinHz, f <= p.persistBandMaxHz else { continue }
            if avg[k] >= strongBar, isLocalMax(k) { chosenBin = k; break }
        }
        guard chosenBin >= 0 else { return reject("nofund") }
        let dominantHz = interpolatedFreq(chosenBin)
        dbg += String(format: " · f %.0f", dominantHz)
        if refBin > 0, abs(refBin - chosenBin) > 1 {
            dbg += String(format: " · dom %.0f", Double(refBin) * binHzP)
        }

        // Annotation — local crest of the chosen peak on the
        // persistent spectrum (the v2.2 neighbourhood rule). No
        // longer a rejection: it prices the confidence.
        let crestNeighbours = (1..<avg.count).filter { k in
            let f = Double(k) * binHzP
            return f >= p.bandMinHz && f <= p.persistBandMaxHz
                && abs(f - dominantHz) >= p.crestNeighbourMinHz
                && abs(f - dominantHz) <= p.crestNeighbourMaxHz
        }.map { avg[$0] }
        let crestRef = crestNeighbours.isEmpty ? 0 : median(crestNeighbours)
        let crestDb = crestRef > 0 ? 20 * log10(avg[chosenBin] / crestRef) : 0
        dbg += String(format: " · crest %.1f", crestDb)

        var confidenceScale = 1.0
        if crestDb < p.crestDbMin { confidenceScale *= 0.75 }
        if anchorVal >= 0.999 {
            confidenceScale *= 0.85
            dbg += " · clip"
        }

        // Silence guard — the one spectral rejection v2.4 keeps.
        // A non-event (room noise, a handling bump) shows neither a
        // sharp line on the persistent spectrum nor real prominence
        // over the room floor; a genuine knock always shows at
        // least one of the two. Both weak together → not a knock.
        // (Measured: harness silence false positives all sit at
        // crest ≤ 3.0 dB and prominence ≤ 23.5 dB; field knocks
        // clear at least one bar by a wide margin, except a
        // −49 dBFS whisper tap that no shipped version has ever
        // answered — it stays UNKNOWN.)
        if crestDb < p.silenceGuardCrestDb, promDb < p.silenceGuardPromDb {
            return reject("flat")
        }

        // Annotation — persistent-spectrum SNR against a noise
        // window (same placement rule as the old segment SNR).
        // Reported and priced into confidence, never a rejection.
        if let noiseStart = noiseSegmentStart(onsetSec: onsetSec, totalSec: Double(samples.count) / Double(sampleRate), sampleRate: sampleRate, p: p),
           let noiseAvg = averagedSpectrum(samples: samples, p: p,
                                           fromSample: noiseStart,
                                           toSample: noiseStart + Int((p.persistWindowEndMs - p.persistWindowStartMs) / 1000.0 * Double(sampleRate))) {
            let bandNoise = (1..<noiseAvg.count).filter {
                let f = Double($0) * binHzP
                return f >= p.bandMinHz && f <= p.persistBandMaxHz
            }.map { noiseAvg[$0] }
            if !bandNoise.isEmpty {
                let ref = max(noiseAvg[chosenBin], median(bandNoise))
                if ref > 0 {
                    let snrDb = 20 * log10(avg[chosenBin] / ref)
                    dbg += String(format: " · snr %.1f", snrDb)
                    if snrDb < p.snrDbMin { confidenceScale *= 0.85 }
                }
            }
        }

        // Centroid over the melon band, on the persistent spectrum.
        var weightedSum = 0.0
        var magSum = 0.0
        for k in 1..<avg.count {
            let freq = Double(k) * binHzP
            guard inBand(freq, p) else { continue }
            weightedSum += freq * avg[k]
            magSum += avg[k]
        }

        return Features(
            heardThump: true,
            dominantHz: dominantHz,
            centroidHz: magSum > 0 ? weightedSum / magSum : 0,
            decayMs: decayMs,
            debug: dbg + " ✓",
            confidenceScale: confidenceScale)
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
    /// The melon band as a closed range (v2.2: 60...600 Hz).
    private static func inBand(_ freq: Double, _ p: HeuristicBandsParametersV24) -> Bool {
        freq >= p.bandMinHz && freq <= p.bandMaxHz
    }

    private static func bandPeak(spectrum: [Double], binHz: Double, p: HeuristicBandsParametersV24) -> BandPeak? {
        var peakMag = 0.0
        var peakBin = 0
        for k in 1..<spectrum.count {
            let freq = Double(k) * binHz
            guard inBand(freq, p) else { continue }
            if spectrum[k] > peakMag {
                peakMag = spectrum[k]
                peakBin = k
            }
        }
        guard peakMag > 0 else { return nil }
        let freq = Double(peakBin) * binHz
        let neighbours = (1..<spectrum.count).filter { k in
            let f = Double(k) * binHz
            return inBand(f, p) && abs(f - freq) >= p.crestNeighbourMinHz && abs(f - freq) <= p.crestNeighbourMaxHz
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
    private static func noiseSegmentStart(onsetSec: Double, totalSec: Double, sampleRate: Int,
                                          p: HeuristicBandsParametersV24) -> Int? {
        let segSec = p.segmentMs / 1000.0
        let after = p.noiseSegmentAfterMs / 1000.0
        let gap = p.noiseSegmentBeforeGapMs / 1000.0
        if onsetSec + after + segSec <= totalSec {
            return Int((onsetSec + after) * Double(sampleRate))
        }
        if onsetSec - gap - segSec >= 0 {
            return Int((onsetSec - gap - segSec) * Double(sampleRate))
        }
        return nil
    }

    /// Mean magnitude spectrum of the STFT frames whose centres lie
    /// in [fromSample, toSample]. The frame grid starts at sample 0
    /// with the model's hop — the same grid the offline recipe that
    /// validated the estimator used. Nil when fewer than two frames
    /// qualify (the averaging is the estimator; one frame is not it).
    private static func averagedSpectrum(samples: [Double], p: HeuristicBandsParametersV24,
                                         fromSample: Int, toSample: Int) -> [Double]? {
        let frame = p.persistFrameSamples
        let hop = p.persistHopSamples
        guard frame >= 256, hop >= 1, samples.count >= frame else { return nil }
        var acc: [Double]?
        var used = 0
        var start = 0
        while start + frame <= samples.count {
            let center = start + frame / 2
            if center >= fromSample, center <= toSample {
                var windowed = [Double](repeating: 0, count: frame)
                for i in 0..<frame {
                    let hann = 0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(frame - 1)))
                    windowed[i] = samples[start + i] * hann
                }
                let mags = fftMagnitudes(windowed)
                if acc == nil { acc = [Double](repeating: 0, count: frame / 2 + 1) }
                for k in 0...(frame / 2) { acc![k] += mags[k] }
                used += 1
            }
            start += hop
        }
        guard used >= 2, var avg = acc else { return nil }
        for k in avg.indices { avg[k] /= Double(used) }
        return avg
    }

    /// The persistent spectrum itself: frames from
    /// persistWindowStartMs to persistWindowEndMs after the anchor.
    private static func persistentSpectrum(samples: [Double], anchorSample: Int, sampleRate: Int,
                                           p: HeuristicBandsParametersV24) -> (mags: [Double], binHz: Double)? {
        let from = anchorSample + Int(p.persistWindowStartMs / 1000.0 * Double(sampleRate))
        let to = anchorSample + Int(p.persistWindowEndMs / 1000.0 * Double(sampleRate))
        guard let mags = averagedSpectrum(samples: samples, p: p, fromSample: from, toSample: to) else { return nil }
        return (mags, Double(sampleRate) / Double(p.persistFrameSamples))
    }

    /// Hann-windowed, zero-padded FFT magnitudes (first half) of
    /// the segment starting at `start`; nil if too short.
    private static func spectrum(samples: [Double], start: Int, sampleRate: Int, durationMs: Double) -> [Double]? {
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

    // MARK: - Heuristic classifier (bands from the model)

    /// f < overripeBelowHz → OVERRIPE; f < ripeUpToHz → RIPE; else
    /// UNRIPE (ripeUpToHz itself is UNRIPE, exactly as v2.2).
    private static func classify(dominantHz f: Double, p: HeuristicBandsParametersV24) -> (verdict: String, confidence: Double) {
        let overripeMaxHz = p.overripeBelowHz
        let ripeMaxHz = p.ripeUpToHz
        if f < overripeMaxHz {
            return ("OVERRIPE", confidence(distanceHz: f, scaleHz: overripeMaxHz, p: p))
        }
        if f < ripeMaxHz {
            let distToEdge = min(f - overripeMaxHz, ripeMaxHz - f)
            return ("RIPE", confidence(distanceHz: distToEdge, scaleHz: (ripeMaxHz - overripeMaxHz) / 2, p: p))
        }
        return ("UNRIPE", confidence(distanceHz: f - ripeMaxHz, scaleHz: p.unripeConfidenceScaleHz, p: p))
    }

    private static func confidence(distanceHz: Double, scaleHz: Double, p: HeuristicBandsParametersV24) -> Double {
        let c = p.confidenceBase + p.confidenceSpan * min(1.0, distanceHz / scaleHz)
        return min(p.confidenceMax, c)
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

// MARK: - frozen parameter set (from ModelFile.swift)

struct HeuristicBandsParametersV24: Equatable, Sendable {
    // Verdict bands.
    var overripeBelowHz: Double
    var ripeUpToHz: Double
    // Verdict confidence: base + span × min(1, distance / scale), capped.
    var confidenceBase: Double
    var confidenceSpan: Double
    var confidenceMax: Double
    var unripeConfidenceScaleHz: Double
    var unknownConfidence: Double
    // Envelope framing and the usable window.
    var envelopeFramesPerSecond: Int
    var trimHeadMs: Double
    var trimTailMs: Double
    var minUsableWindowFrames: Int
    // Time-domain thump gates.
    var absoluteFloor: Double
    var peakWidthMinFrames: Int
    var peakWidthLevelRatio: Double
    var prominenceDbMin: Double
    var attackLevelRatio: Double
    var attackMaxMs: Double
    var decayMaxMs: Double
    var sustainedEndLevelRatio: Double
    // Spectrum.
    var segmentMs: Double
    var segmentPrerollMs: Double
    var bandMinHz: Double
    var bandMaxHz: Double
    var crestNeighbourMinHz: Double
    var crestNeighbourMaxHz: Double
    var crestDbMin: Double
    // Spectral SNR against a noise-only segment.
    var snrDbMin: Double
    var noiseSegmentAfterMs: Double
    var noiseSegmentBeforeGapMs: Double
    // Ring pitch consistency.
    var ringMinOffsetMs: Double
    var ringSegmentMs: Double
    var ringTolerance: Double
    // Persistent-spectrum fundamental estimator (analyzer v2.4).
    // Optional in files; defaults are the validated recipe values.
    var persistWindowStartMs: Double = 20
    var persistWindowEndMs: Double = 400
    var persistFrameSamples: Int = 2048
    var persistHopSamples: Int = 512
    var persistBandMaxHz: Double = 800
    var strongPeakRatio: Double = 0.30
    var fundamentalMinHz: Double = 140
    var silenceGuardCrestDb: Double = 3.5
    var silenceGuardPromDb: Double = 30

    /// Compiled-in fallback: the bundled standard.ml carries the same
    /// values; a DEBUG launch check asserts they agree. This is the
    /// heuristic v2.2 parameter set (formerly `babyV22`), numbers
    /// unchanged by the rename; the v2.3 floor/width values and the
    /// v2.4 estimator keys have since been folded in.
    static let standard = HeuristicBandsParametersV24(
        overripeBelowHz: 160,
        ripeUpToHz: 280,
        confidenceBase: 0.55,
        confidenceSpan: 0.40,
        confidenceMax: 0.95,
        unripeConfidenceScaleHz: 120,
        unknownConfidence: 0.3,
        envelopeFramesPerSecond: 100,
        trimHeadMs: 300,
        trimTailMs: 200,
        minUsableWindowFrames: 10,
        absoluteFloor: 0.002,
        peakWidthMinFrames: 2,
        peakWidthLevelRatio: 0.5,
        prominenceDbMin: 10,
        attackLevelRatio: 0.5,
        attackMaxMs: 80,
        decayMaxMs: 800,
        sustainedEndLevelRatio: 0.6,
        segmentMs: 500,
        segmentPrerollMs: 30,
        bandMinHz: 60,
        bandMaxHz: 600,
        crestNeighbourMinHz: 15,
        crestNeighbourMaxHz: 75,
        crestDbMin: 18,
        snrDbMin: 6,
        noiseSegmentAfterMs: 1200,
        noiseSegmentBeforeGapMs: 300,
        ringMinOffsetMs: 100,
        ringSegmentMs: 250,
        ringTolerance: 0.15,
        persistWindowStartMs: 20,
        persistWindowEndMs: 400,
        persistFrameSamples: 2048,
        persistHopSamples: 512,
        persistBandMaxHz: 800,
        strongPeakRatio: 0.30,
        fundamentalMinHz: 140,
        silenceGuardCrestDb: 3.5,
        silenceGuardPromDb: 30)
}

extension LocalAnalyzerV24 {
    /// The frozen Standard model: frozen parameters, frozen label.
    static let modelLabel = "standard/1.0"

    static func analyze(audioURL: URL) throws -> TapResult {
        try analyze(audioURL: audioURL, parameters: .standard, modelLabel: modelLabel)
    }
}
