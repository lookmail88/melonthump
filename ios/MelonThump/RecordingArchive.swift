import AVFoundation
import Foundation

// MARK: - Recording retention (design doc 1.2.0 §6)
//
// After every completed analysis, the exact WAV file that was fed to
// the analyzer is copied byte-for-byte into Documents/Recordings/ as
// `yyyyMMdd-HHmmss.wav` (device local time), next to a same-named
// `.json` metadata sidecar. Purpose: on-device evidence for
// recognition diagnosis — the user can pull a recording out through
// the Files app (UIFileSharingEnabled) and share it by hand.
//
// Recordings stay on this device only: nothing here touches the
// network, and the folder is excluded from iCloud / iTunes backup.
// Only the newest `maxGroups` groups are kept; older ones are deleted
// automatically. Files that do not follow the archive's own naming
// pattern are never touched.
//
// All file work runs on one private serial queue, so two quick
// analyses can never race the retention sweep. The entry point is
// nonisolated on purpose: a closure formed inside a @MainActor method
// would carry an isolation check that traps on a GCD queue (see
// AudioRecorder's header).
enum RecordingArchive {
    static let maxGroups = 20
    static let folderName = "Recordings"

    /// Everything known on the main thread at analysis time.
    struct Context: Sendable {
        let sourceURL: URL
        let analyzedAt: Date
        let modelId: String
        let modelVersion: String
        let modelDisplayName: String
        let verdict: String
        let confidence: Double
        let dominantFrequencyHz: Double
        let spectralCentroidHz: Double
        let decayTimeMs: Double
        let analyzerLabel: String
        let debugSummary: String?
    }

    /// The JSON sidecar (field names are the on-disk contract).
    struct Metadata: Encodable {
        let schemaVersion: Int
        let recordedAt: String
        let audioFile: String
        let appVersion: String
        let appBuild: String
        let modelId: String
        let modelVersion: String
        let modelDisplayName: String
        let analyzerLabel: String
        let verdict: String
        let confidence: Double
        /// Key omitted when no thump was detected (UNKNOWN).
        let dominantFrequencyHz: Double?
        let spectralCentroidHz: Double?
        let decayTimeMs: Double
        /// Absolute sample peak across all channels, 0…1 linear.
        let peakLevel: Double?
        /// Same peak in dBFS (nil for digital silence / unreadable file).
        let peakLevelDbfs: Double?
        let sampleRate: Double?
        let channelCount: Int?
        let durationSec: Double?
        let debugSummary: String?
    }

    private static let queue = DispatchQueue(label: "dev.xuyang.melonthump.recording-archive",
                                             qos: .utility)

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Fire-and-forget: never blocks the UI, never throws to the caller.
    nonisolated static func save(_ context: Context) {
        queue.async {
            do {
                try performSave(context)
            } catch {
                #if DEBUG
                print("[RecordingArchive] save failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Work (archive queue only)

    private nonisolated static func performSave(_ c: Context) throws {
        let fm = FileManager.default
        var dir = folder
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)

        let stem = uniqueStem(for: c.analyzedAt, in: dir)
        let wavURL = dir.appendingPathComponent(stem + ".wav")
        let jsonURL = dir.appendingPathComponent(stem + ".json")

        // Byte-for-byte copy of the analyzer's input.
        try fm.copyItem(at: c.sourceURL, to: wavURL)

        let audio = audioStats(url: wavURL)
        let heard = c.verdict != "UNKNOWN" && c.dominantFrequencyHz > 0
        let info = Bundle.main.infoDictionary
        let meta = Metadata(
            schemaVersion: 1,
            recordedAt: isoFormatter().string(from: c.analyzedAt),
            audioFile: wavURL.lastPathComponent,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            appBuild: info?["CFBundleVersion"] as? String ?? "?",
            modelId: c.modelId,
            modelVersion: c.modelVersion,
            modelDisplayName: c.modelDisplayName,
            analyzerLabel: c.analyzerLabel,
            verdict: c.verdict,
            confidence: c.confidence,
            dominantFrequencyHz: heard ? c.dominantFrequencyHz : nil,
            spectralCentroidHz: heard ? c.spectralCentroidHz : nil,
            decayTimeMs: c.decayTimeMs,
            peakLevel: audio?.peak,
            peakLevelDbfs: audio.flatMap { $0.peak > 0 ? (20 * log10($0.peak) * 100).rounded() / 100 : nil },
            sampleRate: audio?.sampleRate,
            channelCount: audio?.channels,
            durationSec: audio?.duration,
            debugSummary: c.debugSummary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(meta).write(to: jsonURL, options: .atomic)

        prune(dir: dir)
    }

    /// `yyyyMMdd-HHmmss`, with `-2`, `-3`… appended on a same-second clash.
    private nonisolated static func uniqueStem(for date: Date, in dir: URL) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = f.string(from: date)
        let fm = FileManager.default
        var stem = base
        var n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(stem + ".wav").path)
                || fm.fileExists(atPath: dir.appendingPathComponent(stem + ".json").path) {
            stem = "\(base)-\(n)"
            n += 1
        }
        return stem
    }

    private nonisolated static func isoFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private struct AudioStats {
        let peak: Double
        let sampleRate: Double
        let channels: Int
        let duration: Double
    }

    /// Sample peak of the saved file (all channels). nil if unreadable.
    private nonisolated static func audioStats(url: URL) -> AudioStats? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil,
              let data = buffer.floatChannelData else { return nil }
        var peak: Float = 0
        for ch in 0..<Int(format.channelCount) {
            let p = data[ch]
            for i in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(p[i]))
            }
        }
        return AudioStats(
            peak: (Double(peak) * 10000).rounded() / 10000,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount),
            duration: (Double(file.length) / format.sampleRate * 1000).rounded() / 1000)
    }

    /// Keeps the newest `maxGroups` groups (a group = files sharing one
    /// archive stem). Stems sort chronologically as plain strings.
    private nonisolated static func prune(dir: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        var groups: [String: [String]] = [:]
        for name in names {
            guard let stem = archiveStem(of: name) else { continue }
            groups[stem, default: []].append(name)
        }
        let stems = groups.keys.sorted(by: stemOrder)
        guard stems.count > maxGroups else { return }
        for stem in stems.prefix(stems.count - maxGroups) {
            for name in groups[stem] ?? [] {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    /// Chronological: by timestamp, then by clash suffix (none < -2 < -3…).
    private nonisolated static func stemOrder(_ a: String, _ b: String) -> Bool {
        func split(_ s: String) -> (String, Int) {
            let parts = s.split(separator: "-")
            let ts = parts.prefix(2).joined(separator: "-")
            let n = parts.count > 2 ? Int(parts[2]) ?? 1 : 1
            return (ts, n)
        }
        let (ta, na) = split(a), (tb, nb) = split(b)
        return ta == tb ? na < nb : ta < tb
    }

    /// `yyyyMMdd-HHmmss[-N].wav|json` → stem; anything else → nil.
    private nonisolated static func archiveStem(of name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        guard ext == "wav" || ext == "json" else { return nil }
        let stem = (name as NSString).deletingPathExtension
        guard stem.wholeMatch(of: /\d{8}-\d{6}(-\d+)?/) != nil else { return nil }
        return stem
    }
}
