import SwiftUI

@main
struct MelonThumpApp: App {
    init() {
        // AdMob: consent → ATT → SDK start → rewarded preload.
        // Skipped for DEBUG screenshot runs, so no consent form or ad
        // state can leak into store captures.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-screenshot") }) {
            return
        }
        #endif
        AdsManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-screenshot") }) {
            ScreenshotStage(arg: arg)
        } else {
            VersionGateView()
        }
        #else
        VersionGateView()
        #endif
    }
}

#if DEBUG
/// Store-screenshot stage (DEBUG only, never compiled into release
/// archives): launch with -screenshot-home, -screenshot-recording or
/// -screenshot-result to render that screen directly.
private struct ScreenshotStage: View {
    let arg: String

    var body: some View {
        switch arg {
        case "-screenshot-recording":
            RecordingView(recorder: AudioRecorder(), startedAt: Date(), onStop: {})
        case "-screenshot-result":
            ResultView(
                result: TapResult(
                    dominantFrequencyHz: 212,
                    spectralCentroidHz: 640,
                    decayTimeMs: 180,
                    verdict: "RIPE",
                    confidence: 0.86,
                    modelVersion: "local-v2.2",
                    debugSummary: nil
                ),
                errorMessage: nil,
                onAgain: {}
            )
        default:
            TapView()
        }
    }
}
#endif
