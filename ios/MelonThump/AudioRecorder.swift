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
///
/// Deliberately NOT @MainActor: Swift 6 inserts isolation-entry
/// checks into escaping closures formed inside @MainActor methods,
/// and AVFoundation invokes those closures (the tap block, the
/// record-permission handler) on its own queues, where the check
/// always traps (swift_task_checkIsolated → dispatch_assert_queue_
/// fail, EXC_BREAKPOINT). Keeping this class nonisolated removes the
/// whole family; @Published writes happen on the main queue via
/// explicit dispatch instead.
///
/// @unchecked Sendable: in practice all state is touched from the
/// UI thread — the only background work is the tap's writes to its
/// captured AVAudioFile and AVAudioSession activation — and the
/// conformance lets SwiftUI call sites pass the recorder into tasks
/// without region-isolation errors.
final class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isRecording = false
    @Published var lastRecordingURL: URL?
    /// Normalized live input level 0...1 while recording (drives the
    /// real-time waveform on the recording screen).
    @Published var audioLevel: Double = 0

    private var engine: AVAudioEngine?
    /// Engine whose input prepareToRecord() validated; consumed by the
    /// next startRecording().
    private var preparedEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private let levelBox = LevelBox()

    /// Activates the audio session on a background thread, once, before
    /// any recording.
    func prepareSession() async {
        // .measurement mode: disables the system's voice processing
        // and automatic gain control, which otherwise pump the noise
        // floor up during quiet stretches and destabilize the
        // analyzer's level-based thump gates.
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .measurement)
            try? session.setActive(true)
        }.value
    }

    /// 2.0.1 (TASK-201): re-asserts the session AT THE POINT OF
    /// RECORDING, with real errors. A rewarded ad can hand the session
    /// back inactive / not record-ready after prepareSession() ran (and
    /// that early warm-up swallows its errors). Same category/mode as
    /// prepareSession(); activation stays off the main thread.
    func assertRecordingSession() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement)
            try session.setActive(true)
        }.value
    }

    /// 2.0.1 (TASK-201): must be awaited right before startRecording().
    /// Asserts the session, then checks the input is real (input
    /// available, sampleRate > 0, channelCount > 0). If not: re-asserts
    /// once, waits ~300 ms for the route/session to settle, and checks
    /// again on a fresh engine; still not ready → throws
    /// RecorderError.inputUnavailable. The checked engine is kept for
    /// startRecording(), which re-checks it before installTap anyway.
    func prepareToRecord() async throws {
        preparedEngine = nil
        try await assertRecordingSession()
        var engine = AVAudioEngine()
        if Self.readinessError(of: engine) == nil {
            preparedEngine = engine
            return
        }
        try await assertRecordingSession()
        try await Task.sleep(for: .milliseconds(300))
        engine = AVAudioEngine()
        if let error = Self.readinessError(of: engine) { throw error }
        preparedEngine = engine
    }

    /// nil when the engine's input is safe to tap; otherwise the error to
    /// throw. Reading inputNode/outputFormat never raises — only
    /// installTap does — so this is the guard in front of it.
    private static func readinessError(of engine: AVAudioEngine) -> RecorderError? {
        let format = engine.inputNode.outputFormat(forBus: 0)
        let available = AVAudioSession.sharedInstance().isInputAvailable
        if RecorderReadiness.isInputReady(sampleRate: format.sampleRate,
                                          channelCount: format.channelCount,
                                          inputAvailable: available) {
            return nil
        }
        return .inputUnavailable(sampleRate: format.sampleRate,
                                 channelCount: format.channelCount,
                                 inputAvailable: available)
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

        // 2.0.1: use the engine prepareToRecord() validated, and never
        // feed installTap an invalid format — check again here, BEFORE
        // any AVAudioFile / installTap call (installTap raises an
        // uncatchable NSException on a 0 Hz / 0-channel input).
        let engine = preparedEngine ?? AVAudioEngine()
        preparedEngine = nil
        if let error = Self.readinessError(of: engine) { throw error }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Write the input format as-is (Float32 PCM WAV). LocalAnalyzer
        // decodes with AVAudioFile, which handles it natively.
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.outputFile = file

        levelBox.target = self
        Self.installTap(on: input, format: format, file: file, levelBox: levelBox)

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

    /// Forgets the last take after its result is dismissed ("Thump
    /// Another Melon"), so no stale recording is carried into the next
    /// thump. Only the reference is dropped: the file is in tmp (purged
    /// by the system) and RecordingArchive may still be copying it on
    /// its own queue, so it is not deleted here.
    func clearLastRecording() {
        lastRecordingURL = nil
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
        levelBox: LevelBox
    ) {
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            try? file.write(from: buffer)
            levelBox.update(rmsLevel(of: buffer))
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

/// Thread-safe level forwarder between the audio tap and the UI.
/// The tap block captures only this box (never the recorder itself):
/// passing a self-capturing closure into the nonisolated tap setup is
/// a Swift 6 region-isolation error, and an isolation-inheriting
/// closure would trap on the audio queue. The box republishes each
/// level on the main queue with plain GCD — no actor machinery.
final class LevelBox: @unchecked Sendable {
    weak var target: AudioRecorder?

    func update(_ level: Double) {
        DispatchQueue.main.async { [weak target] in
            target?.audioLevel = level
        }
    }
}
