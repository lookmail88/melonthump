import Foundation

/// 2.0.1 hotfix (TASK-201): pure readiness rule for the recording input,
/// kept free of AVFoundation so ios/Tools/recorder-readiness can
/// compile and test it on macOS without hardware.
///
/// AVAudioEngine RAISES an NSException (uncatchable from Swift, the
/// process aborts) when installTap is handed an input format with no
/// sample rate or no channels — which is what the input node reports
/// when another component (the rewarded-ad SDK) has left the
/// AVAudioSession inactive / not record-ready. AudioRecorder checks
/// this rule before ANY AVAudioFile / installTap call.
enum RecorderReadiness {
    static func isInputReady(sampleRate: Double, channelCount: UInt32, inputAvailable: Bool) -> Bool {
        inputAvailable && sampleRate > 0 && sampleRate.isFinite && channelCount > 0
    }
}

enum RecorderError: LocalizedError {
    /// The session could not provide a usable microphone input (no
    /// input available, or a 0 Hz / 0-channel input format), even after
    /// one re-assertion and a short settle delay.
    case inputUnavailable(sampleRate: Double, channelCount: UInt32, inputAvailable: Bool)

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return L10n.current.t("error.micUnavailable")
        }
    }
}
