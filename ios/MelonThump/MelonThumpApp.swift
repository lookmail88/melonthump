import SwiftUI

@main
struct MelonThumpApp: App {
    init() {
        // .ml models: Baby 1.0 plus a one-time, read-only scan of
        // Documents/Models at launch (design doc 1.2.0 §1).
        _ = ModelRegistry.shared
        RatingPolicy.recordLaunch()
        #if DEBUG
        L10n.assertComplete()
        #endif
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

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootView
                .onChange(of: scenePhase) { _, phase in
                    // Background trigger for the usage-stats queue
                    // (design doc §6).
                    if phase == .background {
                        Task { await StatsReporter.shared.flush() }
                    }
                }
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
/// -screenshot-result to render that screen directly; 1.2.0 adds
/// -screenshot-splash / -menu / -models / -settings(-selector) /
/// -about / -invite for the QA captures of the new UI.
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
        case "-screenshot-splash":
            SplashView()
        case "-screenshot-menu":
            TapView(startWithMenuOpen: true)
        case "-screenshot-models":
            ModelPickerView()
        case "-screenshot-settings":
            SettingsView()
        case "-screenshot-settings-selector":
            SettingsView().onAppear { PolicyStore.shared.debugForceSelector() }
        case "-screenshot-about":
            AboutView()
        case "-screenshot-invite":
            TapView(startWithInviteSheet: true)
        default:
            TapView()
        }
    }
}
#endif
