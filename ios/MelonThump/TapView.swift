import StoreKit
import SwiftUI

/// Main screen: record a tap, upload, show the verdict.
/// UI v4 — Stephanie's design: her original watermelon & cat artwork
/// (Assets.xcassets), her palette (MelonTheme), iPhone portrait layout.
@MainActor
struct TapView: View {
    @StateObject private var recorder = AudioRecorder()
    @ObservedObject private var wallet = CreditWallet.shared
    @ObservedObject private var invites = InviteManager.shared
    @AppStorage("serverEnvironment") private var serverEnvironment: ServerEnvironment = .prod
    @State private var result: TapResult?
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var recordingStartedAt: Date?
    /// Post-promotion session gate (ad, or credits for no ad).
    @State private var showSessionGate = false
    @State private var shareItem: ShareItem?
    @State private var inviteNotice: String?
    @State private var showPromoGate = false
    @State private var menuOpen = false
    @State private var menuDestination: MenuDestination?
    @State private var ratingAskedThisSession = false
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @AppStorage(AppSettings.listeningDurationKey) private var listeningDuration = AppSettings.defaultListeningDuration
    @Environment(\.requestReview) private var requestReview
    private var l: L10n { L10n(preference: languagePref) }
    /// The duration the current recording runs for (fixed at its start).
    @State private var activeRecordingSeconds = AppSettings.defaultListeningDuration
    @State private var showInviteSheet = false

    init(startWithMenuOpen: Bool = false, startWithInviteSheet: Bool = false) {
        _menuOpen = State(initialValue: startWithMenuOpen)
        _showInviteSheet = State(initialValue: startWithInviteSheet)
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            content
            MenuDrawer(isOpen: $menuOpen) { menuDestination = $0 }
        }
        .sheet(item: $menuDestination) { destination in
            switch destination {
            case .models: ModelPickerView()
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
        .alert(l.t("error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(l.t("common.ok"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(l.t("gate.title"), isPresented: $showSessionGate) {
            Button(l.t("gate.watchAd")) { earnWithAd() }
            if wallet.canPayAdFree {
                Button(wallet.adFreeSessionCreditPrice == 1
                       ? l.t("gate.useCredit") : l.f("gate.useCredits", wallet.adFreeSessionCreditPrice)) {
                    wallet.unlockSessionWithCredits()
                }
            }
            Button(l.t("common.notNow"), role: .cancel) {}
        } message: {
            Text(wallet.canPayAdFree ? l.f("gate.messageCredits", wallet.balance) : l.t("gate.messageAd"))
        }
        .sheet(isPresented: $showInviteSheet) { InviteSheet() }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.text]) }
        .alert(inviteNotice ?? "", isPresented: Binding(
            get: { inviteNotice != nil },
            set: { if !$0 { inviteNotice = nil } }
        )) {
            Button(l.t("common.ok"), role: .cancel) { inviteNotice = nil }
        }
        .onChange(of: invites.lastReward) { _, reward in
            if let reward {
                inviteNotice = l.f("invite.reward", reward)
                invites.clearLastReward()
            }
        }
        .onOpenURL { url in
            Task {
                if let outcome = await invites.handle(url: url) {
                    inviteNotice = outcome == .applied ? l.t("invite.linkReceived") : InviteSheet.message(for: outcome, l: l)
                }
            }
        }
        .alert(l.t("promo.title"), isPresented: $showPromoGate) {
            Button(l.t("gate.watchAd")) { earnWithAd() }
            Button(l.t("common.notNow"), role: .cancel) {}
        } message: {
            Text(l.t("promo.message"))
        }
        .task {
            await recorder.prepareSession()
            await wallet.refreshPolicy(environment: AppIdentity.resolvedEnvironment(stored: serverEnvironment))
            await invites.onLaunch(wallet: wallet)
        }
        .onChange(of: serverEnvironment) { _, env in
            Task { await wallet.refreshPolicy(environment: AppIdentity.resolvedEnvironment(stored: env)) }
        }
    }

    private var backgroundColor: Color {
        if let result {
            return Ripeness(verdict: result.verdict).screenTint
        }
        return MelonTheme.background
    }

    @ViewBuilder
    private var content: some View {
        if isAnalyzing {
            AnalyzingView()
        } else if recorder.isRecording {
            RecordingView(recorder: recorder, startedAt: recordingStartedAt ?? Date(),
                          durationSeconds: activeRecordingSeconds, onStop: toggleRecording)
        } else if let result {
            ResultView(result: result, errorMessage: errorMessage) {
                self.result = nil
                self.errorMessage = nil
            }
        } else {
            homeView
        }
    }

    // MARK: - Home (idle)

    private var homeView: some View {
        VStack(spacing: 0) {
            Text("MelonThump")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(MelonTheme.ink)
                .frame(maxWidth: .infinity)
                // Top bar (design doc 1.2.0 §2): hamburger top-left,
                // Invite top-right, laid over the title row's empty
                // margins. An overlay takes no layout space, so none of
                // Stephanie's artwork moves, and nothing covers it.
                .overlay(alignment: .leading) {
                    TopBarButton(systemImage: "line.3.horizontal", label: l.t("home.menu")) {
                        menuOpen = true
                    }
                    .offset(x: -6)
                    .accessibilityIdentifier("topbar.menu")
                }
                .overlay(alignment: .trailing) {
                    TopBarButton(systemImage: "gift", label: l.t("home.invite")) {
                        inviteTapped()
                    }
                    .offset(x: 6)
                    .accessibilityIdentifier("topbar.invite")
                }
            Text(l.t("home.tagline"))
                .font(.custom("Snell Roundhand", size: 21))
                .fontWeight(.bold)
                .foregroundColor(MelonTheme.deepGreen)
                .padding(.top, 2)

            Image("HeroMelon")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 290)
                .padding(.top, 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(l.t("home.howTitle"))
                    .font(.headline)
                    .foregroundColor(MelonTheme.ink)
                Text(l.t("home.howBody"))
                    .font(.subheadline)
                    .foregroundColor(MelonTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(MelonTheme.cream)
            .cornerRadius(24)
            .shadow(color: MelonTheme.ink.opacity(0.13), radius: 8, y: 4)
            .padding(.top, 26)

            Spacer()

            HStack(alignment: .bottom) {
                Image("CatLeft").resizable().scaledToFit().frame(width: 54)
                Spacer()
                Image("CatOrange").resizable().scaledToFit().frame(width: 54)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, -6)

            Button(action: toggleRecording) {
                HStack(spacing: 9) {
                    Circle().fill(Color.white).frame(width: 12, height: 12)
                    Text(l.t("home.start"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(MelonTheme.buttonGreen)
                .foregroundColor(.white)
                .cornerRadius(999)
                .shadow(color: MelonTheme.buttonGreen.opacity(0.35), radius: 10, y: 5)
            }

            Text(l.f("home.hint", AppSettings.sanitizedDuration(listeningDuration)))
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)

            creditsRow
                .padding(.top, 8)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            // 1.2.0: the server selector moved into Settings, behind
            // the server-published version gate (PolicyStore).
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Credits

    @ViewBuilder
    private var creditsRow: some View {
        if wallet.isFreeDay {
            Text(l.t("credits.freeDay"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.needsPromoAd {
            // Launch promo (1.1.0 behaviour, unchanged).
            Button {
                earnWithAd()
            } label: {
                Text(l.t("credits.promoGate"))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(MelonTheme.buttonGreen)
            }
        } else if wallet.isPromoActive {
            Text(l.t("credits.promoUnlocked"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.sessionUnlocked {
            Text(l.t("credits.sessionUnlocked"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.nextThumpIsFirstFree {
            Text(l.t("credits.firstFree"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if !wallet.sessionUnlockEnabled {
            Text(l.t("credits.unlimited"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else {
            Button {
                showSessionGate = true
            } label: {
                Text(wallet.canPayAdFree ? l.f("credits.gateWithBalance", wallet.balance) : l.t("credits.gate"))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(MelonTheme.buttonGreen)
            }
        }
    }

    /// Plays one rewarded ad; on completion it unlocks this app session
    /// (promo or post-promotion gate). Gate ads earn no credits.
    private func earnWithAd() {
        Task {
            if await AdsManager.shared.showRewarded() {
                wallet.unlockSessionWithAd()
            } else if !AdsManager.shared.rewardedReady {
                errorMessage = l.t("ad.loading")
            }
        }
    }

    // MARK: - Actions (unchanged from v1)

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
            recordingStartedAt = nil
            analyze()
        } else {
            guard wallet.canThump else {
                if wallet.needsPromoAd {
                    showPromoGate = true
                } else {
                    showSessionGate = true
                }
                return
            }
            errorMessage = nil
            result = nil
            Task {
                guard await recorder.requestPermission() else {
                    errorMessage = l.t("error.mic")
                    return
                }
                do {
                    // Listening Duration applies from this recording on.
                    activeRecordingSeconds = AppSettings.sanitizedDuration(listeningDuration)
                    try recorder.startRecording()
                    recordingStartedAt = Date()
                } catch {
                    errorMessage = l.f("error.startRecording", error.localizedDescription)
                }
            }
        }
    }

    private func analyze() {
        guard let audioURL = recorder.lastRecordingURL else {
            errorMessage = l.t("error.noRecording")
            return
        }
        isAnalyzing = true
        errorMessage = nil
        Task {
            defer { isAnalyzing = false }
            do {
                // Analysis runs fully on-device; nothing is uploaded.
                // The model is the one picked in the hamburger menu
                // (Baby 1.0 by default), effective from this analysis.
                result = try ModelRegistry.shared.activeModel.analyze(audioURL: audioURL)
                // 1.2.0 allowance: the first real (non-UNKNOWN) analysis
                // uses up the free thump; it is also the invitee's
                // confirmation event for an invite.
                if let verdict = result?.verdict {
                    wallet.recordAnalysis(verdict: verdict)
                    Task { await invites.recordAnalysis(verdict: verdict, wallet: wallet) }
                }
                // Usage stats (1.1.0): only the verdict label is
                // reported — never the recording or any audio data.
                if let verdict = result?.verdict {
                    Task { await StatsReporter.shared.recordAnalysis(verdict: verdict) }
                }
                if result?.verdict == Ripeness.ripe.rawValue {
                    scheduleRatingPrompt()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Rating prompt (design doc 1.2.0 §2)

    /// After a RIPE verdict, for a user past their first sessions: ask
    /// StoreKit for the system rating prompt once the result screen has
    /// settled — never in the first sessions, never while recording or
    /// analyzing, at most once per launch; the system's own throttling
    /// decides whether anything is actually shown.
    private func scheduleRatingPrompt() {
        guard RatingPolicy.isEligible(launchCount: RatingPolicy.launchCount), !ratingAskedThisSession else { return }
        Task {
            try? await Task.sleep(for: .seconds(RatingPolicy.settleDelaySeconds))
            guard result?.verdict == Ripeness.ripe.rawValue, !isAnalyzing, !recorder.isRecording,
                  !menuOpen, menuDestination == nil, errorMessage == nil,
                  !showSessionGate, !showPromoGate, !showInviteSheet, shareItem == nil,
                  inviteNotice == nil, !ratingAskedThisSession else { return }
            ratingAskedThisSession = true
            requestReview()
        }
    }

    // MARK: - Invite

    /// Before the first thump completes: the "Share my invite / I have
    /// a code" choice. Afterwards: straight to the system share sheet.
    private func inviteTapped() {
        if invites.offersCodeEntry {
            showInviteSheet = true
            return
        }
        Task {
            guard let code = await invites.ensureCode() else {
                errorMessage = l.t("invite.err.network")
                return
            }
            shareItem = ShareItem(text: invites.shareText(code: code, l: l))
        }
    }
}

/// Rating-prompt eligibility: launches are counted once per process
/// start; the prompt is considered from the third launch on (past the
/// first sessions). Never mid-flow: only after the result has settled.
enum RatingPolicy {
    static let launchCountKey = "rating.launchCount"
    static let minimumLaunches = 3
    static let settleDelaySeconds = 1.5

    static var launchCount: Int { UserDefaults.standard.integer(forKey: launchCountKey) }

    static func recordLaunch() {
        UserDefaults.standard.set(launchCount + 1, forKey: launchCountKey)
    }

    static func isEligible(launchCount: Int) -> Bool { launchCount >= minimumLaunches }
}

// MARK: - Recording

struct RecordingView: View {
    @ObservedObject var recorder: AudioRecorder
    let startedAt: Date
    /// Listening Duration (Settings): 3 / 5 / 8 s; the countdown follows it.
    var durationSeconds: Int = AppSettings.defaultListeningDuration
    let onStop: () -> Void
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }
    @State private var pulsing = false
    /// Rolling history of live mic levels, oldest → newest (real waveform).
    @State private var levels: [Double] = []
    /// Seconds since recording started, ticked by the countdown task.
    @State private var elapsed: Double = 0

    /// Recording is capped at the listening duration, counted down on screen.
    private var secondsLeft: Int { max(0, Int(ceil(Double(durationSeconds) - elapsed))) }
    /// The user may stop manually once past the third second (with a
    /// 3 s duration the countdown itself ends the recording).
    private static let manualStopAfterSeconds = 3
    private var manualStopPossible: Bool { durationSeconds > Self.manualStopAfterSeconds }
    private var canStop: Bool { manualStopPossible && elapsed > Double(Self.manualStopAfterSeconds) }

    private let barCount = 36

    private func barHeight(at index: Int) -> CGFloat {
        let level = index < levels.count ? levels[index] : 0
        return 6 + CGFloat(level) * 56
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(l.t("rec.listening"))
                .font(.custom("Snell Roundhand", size: 32))
                .fontWeight(.bold)
                .foregroundColor(MelonTheme.deepGreen)
                .padding(.top, 24)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.75), lineWidth: 2.5)
                    .frame(width: 238, height: 238)
                    .scaleEffect(pulsing ? 1.05 : 0.96)
                    .opacity(pulsing ? 0.4 : 0.9)
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: 2.5)
                    .frame(width: 188, height: 188)
                    .scaleEffect(pulsing ? 0.97 : 1.04)
                    .opacity(pulsing ? 0.9 : 0.5)
                Image("HeroMelon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 228)
            }
            .padding(.top, 30)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MelonTheme.deepGreen)
                        .frame(width: 6, height: barHeight(at: i))
                }
            }
            .frame(height: 64)
            .padding(.top, 18)
            .onChange(of: recorder.audioLevel) { _, newLevel in
                levels.append(newLevel)
                if levels.count > barCount {
                    levels.removeFirst(levels.count - barCount)
                }
            }

            VStack(spacing: 0) {
                Text("\(secondsLeft)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundColor(MelonTheme.ink)
                Text(secondsLeft == 1 ? l.t("rec.secondLeft") : l.t("rec.secondsLeft"))
                    .font(.caption)
                    .foregroundColor(MelonTheme.inkSoft)
            }
            .padding(.top, 10)

            Text(l.t("rec.prompt"))
                .font(.subheadline)
                .foregroundColor(MelonTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Spacer()

            Button(action: onStop) {
                Text(l.t("rec.stop"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(MelonTheme.recordRed)
                    .foregroundColor(.white)
                    .cornerRadius(999)
                    .shadow(color: MelonTheme.recordRed.opacity(0.35), radius: 10, y: 5)
            }
            .disabled(!canStop)
            .opacity(canStop ? 1 : 0.55)
            Text(canStop || !manualStopPossible
                 ? l.t("rec.autoStops") : l.f("rec.canStopAfter", Self.manualStopAfterSeconds))
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .task {
            // Countdown over the listening duration: tick the elapsed
            // clock, unlock the stop button after 3s (canStop), and stop
            // & analyze automatically when the countdown runs out.
            while !Task.isCancelled {
                elapsed = max(0, Date().timeIntervalSince(startedAt))
                if elapsed >= Double(durationSeconds) {
                    onStop()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

// MARK: - Analyzing ("please wait" — Stephanie's page)

struct AnalyzingView: View {
    @State private var sheen = false
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        VStack(spacing: 0) {
            Image("PleaseWaitArt")
                .resizable()
                .scaledToFit()
                .cornerRadius(16)
                .shadow(color: MelonTheme.ink.opacity(0.25), radius: 12, y: 6)
                .padding(.top, 16)

            Text(l.t("an.caption"))
                .font(.subheadline)
                .foregroundColor(MelonTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            Spacer()

            Image("LoadingBar")
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.45), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.35)
                        .offset(x: sheen ? geo.size.width * 0.8 : -geo.size.width * 0.4)
                    }
                }
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        sheen = true
                    }
                }

            Text(l.t("an.analyzing"))
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

// MARK: - Result

struct ResultView: View {
    let result: TapResult
    let errorMessage: String?
    let onAgain: () -> Void

    private var ripeness: Ripeness { Ripeness(verdict: result.verdict) }
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        VStack(spacing: 0) {
            Text(l.t("res.badge"))
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(ripeness.accent)
                .cornerRadius(999)
                .padding(.top, 20)

            Image(ripeness.catAsset)
                .resizable()
                .scaledToFit()
                .frame(height: 118)
                .padding(.top, 18)

            Text(ripeness.displayName(l))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(ripeness.accent)
                .padding(.top, 12)

            Text(ripeness.tagline(l))
                .font(.subheadline)
                .foregroundColor(MelonTheme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    stat(value: String(format: "%.0f Hz", result.dominantFrequencyHz), label: l.t("res.dominant"))
                    stat(value: "\(Int(result.confidence * 100))%", label: l.t("res.confidence"))
                    stat(value: String(format: "%.0f ms", result.decayTimeMs), label: l.t("res.decay"))
                }
                ZoneBar(hz: result.dominantFrequencyHz, accent: ripeness.accent)
                Text(thresholdNote)
                    .font(.caption2)
                    .foregroundColor(MelonTheme.inkSoft)
                if let debug = result.debugSummary {
                    Text(debug)
                        .font(.caption2.monospaced())
                        .foregroundColor(MelonTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
            .background(MelonTheme.cream)
            .cornerRadius(24)
            .shadow(color: MelonTheme.ink.opacity(0.13), radius: 8, y: 4)
            .padding(.top, 20)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            Spacer()

            Button(action: onAgain) {
                Text(l.t("res.again"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(MelonTheme.buttonGreen)
                    .foregroundColor(.white)
                    .cornerRadius(999)
                    .shadow(color: MelonTheme.buttonGreen.opacity(0.35), radius: 10, y: 5)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundColor(MelonTheme.ink)
            Text(label)
                .font(.caption2)
                .foregroundColor(MelonTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MelonTheme.background.opacity(0.45))
        .cornerRadius(16)
    }

    /// Band edges of the model in use (Baby 1.0: 160 / 280 Hz).
    private var bands: (low: String, high: String) {
        let p = (ModelRegistry.shared.activeModel as? HeuristicBandsModel)?.parameters ?? .babyV22
        return (String(format: "%g", p.overripeBelowHz), String(format: "%g", p.ripeUpToHz))
    }

    private var thresholdNote: String {
        switch ripeness {
        case .ripe: return l.f("res.ripeRange", bands.low, bands.high)
        case .unripe: return l.f("res.above", bands.high)
        case .overripe: return l.f("res.below", bands.low)
        case .unknown: return l.t("res.unknownNote")
        }
    }
}

/// Gradient scale from unripe (yellow) through ripe (green) to overripe
/// (brown), with a marker at the measured dominant frequency.
/// The axis runs high → low frequency, matching the labels and the
/// physics: a high "ping" is unripe (left), a low thud is overripe
/// (right). Green spans the ripe band, 160–280 Hz.
struct ZoneBar: View {
    let hz: Double
    let accent: Color
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    private var position: Double {
        min(0.98, max(0.02, (350 - hz) / (350 - 100)))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(l.t("zone.unripe")).font(.caption2).foregroundColor(MelonTheme.inkSoft)
                Spacer()
                Text(l.t("zone.ripe")).font(.caption2).foregroundColor(MelonTheme.inkSoft)
                Spacer()
                Text(l.t("zone.overripe")).font(.caption2).foregroundColor(MelonTheme.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.91, green: 0.83, blue: 0.30), location: 0),
                                .init(color: Color(red: 0.56, green: 0.80, blue: 0.42), location: 0.28),
                                .init(color: Color(red: 0.56, green: 0.80, blue: 0.42), location: 0.76),
                                .init(color: Color(red: 0.75, green: 0.52, blue: 0.32), location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(height: 10)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(accent, lineWidth: 3.5))
                        .offset(x: position * (geo.size.width - 18))
                }
            }
            .frame(height: 18)
        }
    }
}
