import SwiftUI

/// Launch-time version gate. The splash doubles as the
/// server-interaction window: on appear it asks the selected server
/// for the client version policy, and the splash lifts only when
/// BOTH at least 3 seconds have elapsed AND the check has concluded
/// (the request itself is capped at 10s — see APIClient; a slow
/// network therefore stretches the splash, up to that cap). So the
/// user never sees the home screen flash before an update prompt:
/// if this build is not the latest version, the blocking update
/// screen is what appears when the splash ends. If the policy
/// cannot be fetched (offline, server down, timeout), the app
/// proceeds — fail-open, per the design.
struct VersionGateView: View {
    @AppStorage("serverEnvironment") private var serverEnvironment: ServerEnvironment = .prod
    @State private var requiredPolicy: ClientVersion?
    @State private var checkFinished = false
    @State private var splashElapsed = false

    private var stillLaunching: Bool { !(checkFinished && splashElapsed) }

    var body: some View {
        ZStack {
            if let policy = requiredPolicy {
                UpdateRequiredView(policy: policy)
            } else {
                TapView()
            }
            if stillLaunching {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            await checkVersion()
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.35)) {
                splashElapsed = true
            }
        }
    }

    private func checkVersion() async {
        defer { checkFinished = true }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let client = APIClient(environment: serverEnvironment)
        // 1.1.0: enroll the App Attest key (first launch that needs
        // it) so the policy fetch can carry an assertion and unlock
        // the server-issued ad unit ID. The extra round-trips ride
        // inside the existing splash window; every failure is silent
        // and the gate stays fail-open.
        _ = await AttestManager.shared.ensureEnrolled(
            environment: serverEnvironment, installId: StatsReporter.installId)
        let canonicalRequest = "GET /api/v1/version/getclientversion?currentVersion=\(current)"
        var headers = await AttestManager.shared.assertionHeaders(
            environment: serverEnvironment, payload: Data(canonicalRequest.utf8))
        if headers == nil && !AttestManager.isSupported {
            headers = AttestManager.bypassHeaders
        }
        do {
            let policy = try await client.fetchClientVersion(
                currentVersion: current, assertionHeaders: headers)
            if let unitID = policy.rewardedAdUnitId, !unitID.isEmpty {
                AdsManager.shared.applyServerRewardedUnitId(unitID)
            }
            // Test mode: Xcode (Debug) builds are never blocked by
            // the gate. A tester pointing a local build at the dev
            // backend — whose latest version tracks the newest code —
            // would otherwise be walled by a policy written for
            // shipped users. Release builds (TestFlight / App Store)
            // keep the exact blocking behavior, and everything else
            // in this check (attested fetch, server ad unit, stats
            // flush) still runs in Debug too.
            #if !DEBUG
            if policy.updateAvailable || policy.forceUpdate {
                requiredPolicy = policy
            }
            #endif
        } catch {
            // Fail-open: no policy, no block.
        }
        // Launch trigger for the usage-stats queue (design doc §6).
        await StatsReporter.shared.flush()
    }
}

/// Full-screen launch image: the app icon artwork (SplashIcon,
/// copied from the AppIcon set) centered and enlarged on the
/// theme background. Shown while the version gate resolves.
struct SplashView: View {
    var body: some View {
        ZStack {
            MelonTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .shadow(color: MelonTheme.ink.opacity(0.18), radius: 16, y: 8)
                Text("MelonThump")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(MelonTheme.ink)
                    .padding(.top, 22)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")")
                    .font(.footnote)
                    .foregroundColor(MelonTheme.inkSoft)
                    .padding(.top, 6)
                Text("powered by xgao&sgao")
                    .font(.footnote)
                    .foregroundColor(MelonTheme.inkSoft)
                    .padding(.top, 2)
            }
        }
    }
}

/// Full-screen, non-dismissible update prompt (Stephanie's palette).
struct UpdateRequiredView: View {
    let policy: ClientVersion
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            MelonTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Image("HeroMelon")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
                    .padding(.top, 48)

                Text("Time to update!")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(MelonTheme.ink)
                    .padding(.top, 24)

                Text("A newer version of MelonThump is ready.\nPlease update to keep thumping.")
                    .font(.subheadline)
                    .foregroundColor(MelonTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                Text("Latest version: \(policy.latestVersion)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(MelonTheme.deepGreen)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(MelonTheme.cream)
                    .cornerRadius(999)
                    .padding(.top, 18)

                Spacer()

                Button {
                    if let url = URL(string: policy.updateUrl), !policy.updateUrl.isEmpty {
                        openURL(url)
                    }
                } label: {
                    Text("Get the Latest Version")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(MelonTheme.buttonGreen)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                        .shadow(color: MelonTheme.buttonGreen.opacity(0.35), radius: 10, y: 5)
                }
                .disabled(policy.updateUrl.isEmpty)
                .opacity(policy.updateUrl.isEmpty ? 0.5 : 1)

                if policy.updateUrl.isEmpty {
                    Text("The update link is not configured yet.")
                        .font(.caption)
                        .foregroundColor(MelonTheme.inkSoft)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
    }
}
