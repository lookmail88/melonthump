import SwiftUI

/// Launch-time version gate. On appear it asks the selected server for
/// the client version policy; if this build is not the latest version,
/// a blocking update screen replaces the app and sends the user to the
/// App Store. If the policy cannot be fetched (offline, server down),
/// the app proceeds — fail-open, per the design.
struct VersionGateView: View {
    @AppStorage("serverEnvironment") private var serverEnvironment: ServerEnvironment = .prod
    @State private var requiredPolicy: ClientVersion?

    var body: some View {
        Group {
            if let policy = requiredPolicy {
                UpdateRequiredView(policy: policy)
            } else {
                TapView()
            }
        }
        .task {
            await checkVersion()
        }
    }

    private func checkVersion() async {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let client = APIClient(environment: serverEnvironment)
        do {
            let policy = try await client.fetchClientVersion(currentVersion: current)
            if policy.updateAvailable || policy.forceUpdate {
                requiredPolicy = policy
            }
        } catch {
            // Fail-open: no policy, no block.
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
