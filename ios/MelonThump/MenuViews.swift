import SwiftUI

/// Local settings (design doc 1.2.0 §2).
enum AppSettings {
    /// Listening duration in seconds: 3 / 5 (default) / 8. Persisted;
    /// read when a recording starts, so a change applies to the next one.
    static let listeningDurationKey = "settings.listeningDurationSeconds"
    static let listeningDurations = [3, 5, 8]
    static let defaultListeningDuration = 5

    static func sanitizedDuration(_ value: Int) -> Int {
        listeningDurations.contains(value) ? value : defaultListeningDuration
    }

    static let supportEmail = "support@stephaniegao.me"
    static let privacyURL = URL(string: "https://lookmail88.github.io/melonthump/privacy.html")!
    /// No MelonThump-specific terms page exists yet; the App Store
    /// listing uses Apple's Standard EULA, so that is what we link.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let githubURL = URL(string: "https://github.com/lookmail88/melonthump#readme")!

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}

// MARK: - Top bar buttons

/// Round top-bar button in the app's existing design language (cream
/// disc, ink glyph, the same soft shadow the cards use).
struct TopBarButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MelonTheme.ink)
                .frame(width: 40, height: 40)
                .background(MelonTheme.cream.opacity(0.92))
                .clipShape(Circle())
                .shadow(color: MelonTheme.ink.opacity(0.13), radius: 6, y: 3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Hamburger drawer

enum MenuDestination: String, Identifiable {
    case models, settings, about
    var id: String { rawValue }
}

/// Slide-in drawer from the left. Exactly three entries (decided
/// 2026-11-04): Model picker / Settings / About — no History.
struct MenuDrawer: View {
    @Binding var isOpen: Bool
    let onSelect: (MenuDestination) -> Void
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MelonThump")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(MelonTheme.ink)
                        .padding(.top, 24)
                        .padding(.bottom, 22)
                    row(.models, icon: "waveform.badge.magnifyingglass", title: l.t("menu.models"))
                    row(.settings, icon: "gearshape", title: l.t("menu.settings"))
                    row(.about, icon: "info.circle", title: l.t("menu.about"))
                    Spacer()
                    Text(l.f("splash.version", AppSettings.versionString))
                        .font(.footnote)
                        .foregroundColor(MelonTheme.inkSoft)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 22)
                .frame(width: 280, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                    MelonTheme.cream
                        .shadow(color: MelonTheme.ink.opacity(0.2), radius: 12, x: 4)
                        .ignoresSafeArea())
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeOut(duration: 0.25), value: isOpen)
    }

    private func row(_ destination: MenuDestination, icon: String, title: String) -> some View {
        Button {
            close()
            onSelect(destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MelonTheme.buttonGreen)
                    .frame(width: 28)
                Text(title)
                    .font(.headline)
                    .foregroundColor(MelonTheme.ink)
                Spacer()
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("menu.\(destination.rawValue)")
    }

    private func close() { isOpen = false }
}

// MARK: - Model picker

/// Lists every available model with its state — Default / Free / Paid
/// (price, or Purchased). 1.2.0 ships Baby 1.0 only (default, free
/// forever) plus any valid external files; the paid row rendering
/// exists for a later release, but no paid model and no StoreKit flow
/// ship now. A selection persists and applies from the next analysis.
struct ModelPickerView: View {
    @ObservedObject var registry = ModelRegistry.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @Environment(\.dismiss) private var dismiss
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(registry.models.map(\.descriptor)) { model in
                        Button {
                            select(model)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.displayName)
                                        .font(.headline)
                                        .foregroundColor(MelonTheme.inkAdaptive)
                                    Text(l.f("models.version", model.modelVersion))
                                        .font(.caption)
                                        .foregroundColor(MelonTheme.inkSoftAdaptive)
                                }
                                Spacer()
                                ForEach(badges(for: model), id: \.self) { badge in
                                    Text(badge)
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(MelonTheme.buttonGreen)
                                        .cornerRadius(999)
                                }
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(MelonTheme.buttonGreenAdaptive)
                                    .opacity(registry.activeModel.descriptor.modelId == model.modelId ? 1 : 0)
                            }
                        }
                    }
                } footer: {
                    Text(l.t("models.footer"))
                }
            }
            .navigationTitle(l.t("models.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l.t("common.done")) { dismiss() }
                }
            }
        }
    }

    private func badges(for model: ModelDescriptor) -> [String] {
        var out: [String] = []
        if model.isDefault { out.append(l.t("models.default")) }
        switch model.offer {
        case .free:
            out.append(l.t("models.free"))
        case .paid:
            // Later release: show the StoreKit price, or Purchased.
            out.append(l.t("models.paid"))
        }
        return out
    }

    private func select(_ model: ModelDescriptor) {
        switch model.offer {
        case .free:
            registry.selectedId = model.modelId
        case .paid:
            // No purchase flow in 1.2.0 (no paid model ships).
            break
        }
    }
}

// MARK: - Settings (modeled on Retax's Settings page)

struct SettingsView: View {
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @AppStorage(AppSettings.listeningDurationKey) private var listeningDuration = AppSettings.defaultListeningDuration
    @AppStorage("serverEnvironment") private var serverEnvironment: ServerEnvironment = .prod
    @ObservedObject private var policy = PolicyStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        NavigationStack {
            List {
                // Language — follows the system by default.
                Section {
                    choiceRow(l.t("set.followSystem"), selected: AppLanguage(rawValue: languagePref) == nil) {
                        languagePref = L10n.followSystem
                    }
                    ForEach(AppLanguage.allCases) { lang in
                        choiceRow(lang.displayName, selected: languagePref == lang.rawValue) {
                            languagePref = lang.rawValue
                        }
                    }
                } header: {
                    Text(l.t("set.language"))
                }

                // Listening Duration — 3 / 5 (default) / 8 s.
                Section {
                    ForEach(AppSettings.listeningDurations, id: \.self) { seconds in
                        choiceRow(seconds == AppSettings.defaultListeningDuration
                                      ? l.f("set.secondsDefault", seconds) : l.f("set.seconds", seconds),
                                  selected: AppSettings.sanitizedDuration(listeningDuration) == seconds) {
                            listeningDuration = seconds
                        }
                    }
                } header: {
                    Text(l.t("set.duration"))
                } footer: {
                    Text(l.t("set.durationFooter"))
                }

                // Server selector — only when the server-published
                // versions unlock it (see PolicyStore.serverSelectorUnlocked).
                if policy.serverSelectorUnlocked {
                    Section {
                        Picker(l.t("set.server"), selection: $serverEnvironment) {
                            ForEach(ServerEnvironment.allCases) { env in
                                Text(env.displayName(l)).tag(env)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text(l.t("set.server"))
                    } footer: {
                        Text(l.t("set.serverFooter"))
                    }
                }

                // Feedback (ported from Retax 550b315): system mail
                // composer via mailto, nothing sent to our server.
                Section {
                    Button(action: openFeedbackMail) {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(MelonTheme.buttonGreenAdaptive)
                            Text(l.t("set.feedback"))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote).bold()
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Development Team — after Feedback, above About.
                Section {
                    NavigationLink {
                        TeamView()
                    } label: {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(MelonTheme.buttonGreenAdaptive)
                            Text(l.t("set.team"))
                                .foregroundColor(.primary)
                        }
                    }
                }

                // About — below Feedback, as in Retax.
                Section {
                    NavigationLink {
                        AboutContent()
                    } label: {
                        HStack {
                            Text(l.t("set.about"))
                            Spacer()
                            Text("MelonThump").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text(l.t("set.version"))
                        Spacer()
                        Text(AppSettings.versionString).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(l.t("set.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l.t("common.done")) { dismiss() }
                }
            }
        }
    }

    private func choiceRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundColor(MelonTheme.buttonGreenAdaptive)
                }
            }
        }
    }

    /// Mirrors Retax's openFeedbackMail: recipient prefilled, subject
    /// prefilled, the app version appended to the body; stateless.
    private func openFeedbackMail() {
        if let url = Self.feedbackMailURL(subject: l.t("set.feedbackSubject")) {
            openURL(url)
        }
    }

    static func feedbackMailURL(subject: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppSettings.supportEmail
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: "\n\n\u{2014}\nMelonThump " + version),
        ]
        return components.url
    }
}

// MARK: - Development Team

/// The five launch-screen credits (SplashView.creditLines), verbatim and
/// in the same order. Labels stay in the English original in every UI
/// language; only the page title localizes.
struct TeamView: View {
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    static let members: [(role: String, name: String)] = [
        ("UI Designer", "Stephanie Gao"),
        ("Project Owner", "Xuyang Gao"),
        ("Architecture", "Xuyang Gao"),
        ("Developer", "Claude"),
        ("BA/QA", "Pepper"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.members, id: \.role) { member in
                    HStack {
                        Text(member.role)
                            .foregroundColor(MelonTheme.inkSoftAdaptive)
                        Spacer()
                        Text(member.name)
                            .font(.body.weight(.semibold))
                            .foregroundColor(MelonTheme.inkAdaptive)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(l.t("team.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About

/// App version, privacy policy, terms, contact, and the project README
/// on GitHub (opens in the browser).
struct AboutView: View {
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @Environment(\.dismiss) private var dismiss
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        NavigationStack {
            AboutContent()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(l.t("common.done")) { dismiss() }
                    }
                }
        }
    }
}

struct AboutContent: View {
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("MelonThump")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(MelonTheme.inkAdaptive)
                    Text(l.t("about.blurb"))
                        .font(.subheadline)
                        .foregroundColor(MelonTheme.inkSoftAdaptive)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                HStack {
                    Text(l.t("about.version"))
                    Spacer()
                    Text(AppSettings.versionString).foregroundColor(.secondary)
                }
                link(l.t("about.privacy"), icon: "hand.raised", url: AppSettings.privacyURL)
                link(l.t("about.terms"), icon: "doc.text", url: AppSettings.termsURL)
                link(l.t("about.contact"), icon: "envelope", url: URL(string: "mailto:\(AppSettings.supportEmail)")!,
                     detail: AppSettings.supportEmail)
                link(l.t("about.github"), icon: "book", url: AppSettings.githubURL,
                     detail: "github.com/lookmail88/melonthump")
            }
        }
        .navigationTitle(l.t("about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ title: String, icon: String, url: URL, detail: String? = nil) -> some View {
        Link(destination: url) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(MelonTheme.buttonGreenAdaptive)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary)
                    if let detail {
                        Text(detail).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote).bold()
                    .foregroundColor(.secondary)
            }
        }
    }
}
