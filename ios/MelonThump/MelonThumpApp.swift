import SwiftUI

@main
struct MelonThumpApp: App {
    /// Launch splash: the app icon, enlarged, shown for 3 seconds
    /// over the home screen (which warms up underneath — version
    /// check and audio-session prep run during the splash).
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                VersionGateView()
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
        }
    }
}

/// Full-screen launch image: the app icon artwork (SplashIcon,
/// copied from the AppIcon set) centered and enlarged on the
/// theme background.
struct SplashView: View {
    var body: some View {
        ZStack {
            MelonTheme.background.ignoresSafeArea()
            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                .shadow(color: MelonTheme.ink.opacity(0.18), radius: 16, y: 8)
        }
    }
}
