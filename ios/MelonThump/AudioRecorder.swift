import AVFoundation
import Foundation

/// Records tap audio to a WAV file with AVAudioEngine.
///
/// AVAudioRecorder was replaced on purpose: its record() synchronously
/// re-activates the AVAudioSession on the main thread every time, which
/// makes AVAudioSession log a "UI unresponsiveness" warning that
/// pre-activating the session does not silence. The engine never does
/// that — the session is activated once, off the main thread
/// (see prepareSession()).
///
/// Live levels for the recording screen's waveform are computed from
/// the tapped buffers (RMS), so no meter polling is needed either.
/// @MainActor: all engine/file state is only touched on the main actor;
/// the realtime tap block only writes the file and forwards levels.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var lastRecordingURL: URL?
    /// Normalized live input level 0...1 while recording (drives the
    /// real-time waveform on the recording screen).
    @Published var audioLevel: Double = 0

    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?

    /// Activates the audio session on a background thread, once, before
    /// any recording.
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

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Write the input format as-is (Float32 PCM WAV). LocalAnalyzer
        // decodes with AVAudioFile, which handles it natively.
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.outputFile = file

        Self.installTap(on: input, format: format, file: file) { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        self.lastRecordingURL = url
        self.isRecording = true
    }

    func stopRecording() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil
        isRecording = false
        audioLevel = 0
    }

    /// Installs the recording tap. This MUST stay nonisolated and create
    /// the tap block here: a block literal formed inside the @MainActor
    /// startRecording() inherits MainActor isolation, so Swift inserts
    /// a swift_task_checkIsolated assertion at the block's entry — and
    /// AVFAudio invokes the block on its RealtimeMessenger queue, where
    /// that assertion always fails (dispatch_assert_queue_fail,
    /// EXC_BREAKPOINT on device). Formed in a nonisolated context and
    /// capturing only nonisolated values, the block carries no check.
    private nonisolated static func installTap(
        on input: AVAudioNode,
        format: AVAudioFormat,
        file: AVAudioFile,
        onLevel: @escaping @Sendable (Double) -> Void
    ) {
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            try? file.write(from: buffer)
            onLevel(rmsLevel(of: buffer))
        }
    }

    /// RMS of the first channel mapped to 0...1 (roughly -50 dB…0 dB).
    private nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let channel = data[0]
        var sum: Float = 0
        for i in 0..<frames {
            sum += channel[i] * channel[i]
        }
        let rms = sqrt(sum / Float(frames))
        guard rms > 0 else { return 0 }
        let db = 20 * log10(Double(rms))
        return min(1, max(0, (db + 50) / 45))
    }
}
