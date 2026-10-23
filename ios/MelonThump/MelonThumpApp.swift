import SwiftUI

@main
struct MelonThumpApp: App {
    init() {
        // AdMob: consent → ATT → SDK start → rewarded preload.
        AdsManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            VersionGateView()
        }
    }
}
