import AVFoundation
import Foundation

/// Records tap audio as 16-bit PCM WAV via AVAudioRecorder.
/// @MainActor: AVAudioRecorder is not Sendable; all use stays on the main actor.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var lastRecordingURL: URL?
    /// Normalized live input level 0...1 while recording (drives the
    /// real-time waveform on the recording screen).
    @Published var audioLevel: Double = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?

    /// Activates the audio session on a background thread, once, before
    /// any recording. If this is left to AVAudioRecorder.record() on the
    /// main thread, AVAudioSession logs a "UI unresponsiveness" warning.
    func prepareSession() async {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .default)
            try? session.setActive(true)
        }.value
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tap-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        self.lastRecordingURL = url
        self.isRecording = true
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollLevel()
            }
        }
    }

    func stopRecording() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        audioLevel = 0
    }

    private func pollLevel() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = Double(recorder.averagePower(forChannel: 0))
        // averagePower is in dB, roughly -50 (quiet room) to 0 (loudest).
        audioLevel = min(1, max(0, (db + 50) / 45))
    }
}
