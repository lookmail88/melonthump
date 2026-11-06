import SwiftUI

/// Launch-time version gate. The splash doubles as the
/// server-interaction window: on appear it asks the selected server
/// for the client version policy, and the splash lifts only when
/// BOTH at least 3 seconds have elapsed AND the check has concluded
/// (the request itself is capped at 10s — see APIClient; a slow
/// network therefore stretches the splash, up to that cap). So the
/// user never sees the home screen flash before an update prompt.
/// Two tiers, by the policy's forceUpdate flag: a forced update
/// (this build is below the minimum supported version) gets the
/// blocking update screen when the splash ends; a soft update
/// (a newer version exists but this build is still supported)
/// only gets a dismissible alert, once per version, and only when
/// an update link is configured — never a wall. If the policy
/// cannot be fetched (offline, server down, timeout), the app
/// proceeds — fail-open, per the design.
struct VersionGateView: View {
    @AppStorage("serverEnvironment") private var serverEnvironment: ServerEnvironment = .prod
    @AppStorage("softUpdateDismissedVersion") private var softUpdateDismissedVersion: String = ""
    @Environment(\.openURL) private var openURL
    @State private var requiredPolicy: ClientVersion?
    @State private var softUpdatePolicy: ClientVersion?
    @State private var showSoftUpdate = false
    @State private var checkFinished = false
    @State private var splashElapsed = false
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    private var stillLaunching: Bool { !(checkFinished && splashElapsed) }

    /// The stored selection resolved for this build's channel —
    /// TestFlight / App Store builds always check against prod.
    private var effectiveEnvironment: ServerEnvironment {
        AppIdentity.resolvedEnvironment(stored: serverEnvironment)
    }

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
        .alert(l.t("upd.softTitle"), isPresented: $showSoftUpdate, presenting: softUpdatePolicy) { policy in
            Button(l.t("upd.notNow")) {
                softUpdateDismissedVersion = policy.latestVersion
            }
            Button(l.t("upd.update")) {
                softUpdateDismissedVersion = policy.latestVersion
                if let url = URL(string: policy.updateUrl) {
                    openURL(url)
                }
            }
        } message: { policy in
            Text(l.f("upd.softMessage", policy.latestVersion))
        }
        .task {
            await checkVersion()
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.35)) {
                splashElapsed = true
            }
            if softUpdatePolicy != nil {
                showSoftUpdate = true
            }
        }
    }

    private func checkVersion() async {
        defer { checkFinished = true }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let client = APIClient(environment: effectiveEnvironment)
        // 1.1.0: enroll the App Attest key (first launch that needs
        // it) so the policy fetch can carry an assertion and unlock
        // the server-issued ad unit ID. The extra round-trips ride
        // inside the existing splash window; every failure is silent
        // and the gate stays fail-open.
        _ = await AttestManager.shared.ensureEnrolled(
            environment: effectiveEnvironment, installId: StatsReporter.installId)
        let canonicalRequest = "GET /api/v1/version/getclientversion?currentVersion=\(current)"
        var headers = await AttestManager.shared.assertionHeaders(
            environment: effectiveEnvironment, payload: Data(canonicalRequest.utf8))
        if headers == nil && !AttestManager.isSupported {
            headers = AttestManager.bypassHeaders
        }
        do {
            let policy = try await client.fetchClientVersion(
                currentVersion: current, assertionHeaders: headers)
            if let unitID = policy.rewardedAdUnitId, !unitID.isEmpty {
                AdsManager.shared.applyServerRewardedUnitId(unitID)
            }
            if effectiveEnvironment == .prod {
                PolicyStore.shared.applyProdPolicy(policy)
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
            if policy.forceUpdate {
                requiredPolicy = policy
            } else if policy.updateAvailable, !policy.updateUrl.isEmpty,
                      softUpdateDismissedVersion != policy.latestVersion {
                // Soft update: remember it for a dismissible alert
                // once the splash lifts (see the timer task). With
                // no update link configured there is nothing the
                // user could do, so it stays silent rather than
                // nagging — and it never blocks.
                softUpdatePolicy = policy
            }
            #endif
        } catch {
            // Fail-open: no policy, no block.
        }
        // 1.2.0 server-selector gate: evaluated on the prod policy. A
        // build pointed at Dev (Xcode only) asks prod separately; any
        // failure keeps the selector hidden.
        if effectiveEnvironment != .prod {
            let prodPolicy = try? await APIClient(environment: .prod).fetchClientVersion(currentVersion: current)
            PolicyStore.shared.applyProdPolicy(prodPolicy)
        }
        // Launch trigger for the usage-stats queue (design doc §6).
        await StatsReporter.shared.flush()
    }
}

/// Full-screen launch image: the app icon artwork (SplashIcon,
/// copied from the AppIcon set) centered and enlarged on the
/// theme background. Shown while the version gate resolves.
struct SplashView: View {
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    /// Role credits (design doc 1.2.0 §2, revised 2026-11-04): roles
    /// localize, the names are never translated.
    private var creditLines: [String] {
        let sep = l.t("credit.separator")
        return [
            l.t("credit.uiDesigner") + sep + "Stephanie Gao",
            l.t("credit.projectOwner") + sep + "Xuyang Gao",
            l.t("credit.architecture") + sep + "Xuyang Gao",
            l.t("credit.developer") + sep + "Claude",
            l.t("credit.baqa") + sep + "Pepper",
        ]
    }

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
                Text(l.f("splash.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"))
                    .font(.footnote)
                    .foregroundColor(MelonTheme.inkSoft)
                    .padding(.top, 6)
                // Where the single "powered by" line used to be: an
                // invisible line of the same metrics, so the centered
                // icon artwork stays exactly where it was.
                Text("powered by xgao&sgao")
                    .font(.footnote)
                    .padding(.top, 2)
                    .hidden()
                    .accessibilityHidden(true)
            }
            // Five role credits, low on the screen near the bottom and
            // clear of the artwork (the icon art above stays centered,
            // exactly where it was).
            VStack(spacing: 3) {
                ForEach(creditLines, id: \.self) { line in
                    Text(line)
                }
            }
            .font(.caption)
            .foregroundColor(MelonTheme.inkSoft)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 18)
        }
    }
}

/// Full-screen, non-dismissible update prompt (Stephanie's palette).
struct UpdateRequiredView: View {
    let policy: ClientVersion
    @Environment(\.openURL) private var openURL
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        ZStack {
            MelonTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Image("HeroMelon")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
                    .padding(.top, 48)

                Text(l.t("upd.title"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(MelonTheme.ink)
                    .padding(.top, 24)

                Text(l.t("upd.body"))
                    .font(.subheadline)
                    .foregroundColor(MelonTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                Text(l.f("upd.latest", policy.latestVersion))
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
                    Text(l.t("upd.get"))
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
                    Text(l.t("upd.noLink"))
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
