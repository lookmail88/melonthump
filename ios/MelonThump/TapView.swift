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
    /// 2.0 contributor program (ad-free units at the gates).
    @ObservedObject private var program = ContributorProgram.shared
    /// 2.0: the melon record the next thump belongs to, when the user
    /// chose "Thump this melon" in a record; nil = the home flow, which
    /// files the thump into a record in the background.
    @State private var continuingRecordId: UUID?
    /// FIX1: the record the shown result was filed into (attachThump's
    /// record id), for the result's "Photograph this melon" button; nil =
    /// not attached, and the button is simply absent.
    @State private var resultRecordId: UUID?
    /// FIX1: that record's detail (Step 1 = appearance photos) is open.
    @State private var showResultRecord = false
    /// FIX2 photo gate: the record a start was refused for (it lacks its
    /// appearance photos); its capture sheet is open while this is set.
    @State private var photoGateRecordId: UUID?
    /// FIX2: the record the photo gate passed for the running recording,
    /// so the analysis is filed exactly where the gate looked.
    @State private var gatedRecordId: UUID?
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
    /// FIX8: the promo gate was raised by the 开始验瓜 journey entry; once
    /// the session unlocks (ad watched or ad-free unit spent) the journey
    /// continues by itself. Cleared on "Not now" / a failed unlock.
    @State private var resumeJourneyAfterUnlock = false
    @State private var menuOpen = false
    @State private var menuDestination: MenuDestination?
    @State private var ratingAskedThisSession = false
    /// The pending post-RIPE rating prompt (cancelled by "Thump Another
    /// Melon", so it can never fire for a cleared result).
    @State private var ratingPromptTask: Task<Void, Never>?
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @AppStorage(AppSettings.listeningDurationKey) private var listeningDuration = AppSettings.defaultListeningDuration
    @Environment(\.requestReview) private var requestReview
    private var l: L10n { L10n(preference: languagePref) }
    /// The duration the current recording runs for (fixed at its start).
    @State private var activeRecordingSeconds = AppSettings.defaultListeningDuration
    @State private var showInviteSheet = false

    #if DEBUG
    /// DEBUG stage only (-screenshot-next-melon-tap): press "Thump
    /// Another Melon" after a delay.
    private var debugAutoNextMelon = false
    #endif

    init(startWithMenuOpen: Bool = false, startWithInviteSheet: Bool = false) {
        _menuOpen = State(initialValue: startWithMenuOpen)
        _showInviteSheet = State(initialValue: startWithInviteSheet)
    }

    #if DEBUG
    init(debugStartResult: TapResult, autoNextMelon: Bool) {
        _result = State(initialValue: debugStartResult)
        debugAutoNextMelon = autoNextMelon
    }
    #endif

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            content
            MenuDrawer(isOpen: $menuOpen) { menuDestination = $0 }
        }
        .sheet(item: $menuDestination) { destination in
            switch destination {
            case .models: ModelPickerView()
            case .records: RecordsListView(onThump: thumpForRecord)
            case .program: ProgramMenuSheet()
            // Never set: the drawer's Feedback row opens the mail
            // composer directly (MenuDrawer.openFeedbackMail).
            case .feedback: EmptyView()
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
        .sheet(isPresented: $showResultRecord) {
            // FIX1: the same RecordDetailView My Melons pushes, in a sheet
            // with its own NavigationStack and the list's Done button.
            if let id = resultRecordId {
                recordSheet(id) { showResultRecord = false }
            }
        }
        .sheet(isPresented: Binding(
            get: { photoGateRecordId != nil },
            set: { if !$0 { photoGateRecordId = nil } }
        ), onDismiss: photoGateDismissed) {
            // FIX2: a start refused by the photo gate lands here — the
            // same capture sheet, Step 1 on top with the photos-first
            // notice; its "Thump this melon" unlocks with both photos.
            if let id = photoGateRecordId {
                recordSheet(id) { photoGateRecordId = nil }
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
            if program.canSpendAdFree {
                Button(l.f("gate.useAdFree", program.adFreeBalance)) { spendAdFreeUnit() }
            }
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
            if program.canSpendAdFree {
                Button(l.f("gate.useAdFree", program.adFreeBalance)) { spendAdFreeUnit() }
            }
            Button(l.t("common.notNow"), role: .cancel) { resumeJourneyAfterUnlock = false }
        } message: {
            Text(l.t("promo.message"))
        }
        .task {
            await recorder.prepareSession()
            await wallet.refreshPolicy(environment: AppIdentity.resolvedEnvironment(stored: serverEnvironment))
            await invites.onLaunch(wallet: wallet)
        }
        .task {
            // 2.0: contributor standing (ad-free balance / permanent
            // exemption). Silent and fail-soft; no id = no request.
            await program.refresh()
        }
        .onChange(of: serverEnvironment) { _, env in
            Task { await wallet.refreshPolicy(environment: AppIdentity.resolvedEnvironment(stored: env)) }
        }
        #if DEBUG
        .task {
            guard debugAutoNextMelon else { return }
            // Leftovers a real thump can leave behind that are invisible
            // on the result screen (the visible ones — alerts, sheets,
            // the drawer — cover the button, so it can't be pressed).
            recordingStartedAt = Date()
            recorder.lastRecordingURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("tap-debug.wav")
            ratingPromptTask = Task { try? await Task.sleep(for: .seconds(3600)) }
            try? await Task.sleep(for: .seconds(2))
            print("[next-melon] before: \(debugFlowState)")
            startNextMelon()
            print("[next-melon] after:  \(debugFlowState)")
        }
        #endif
    }

    #if DEBUG
    private var debugFlowState: String {
        "screen=\(isAnalyzing ? "analyzing" : recorder.isRecording ? "recording" : result != nil ? "result" : "home")"
        + " result=\(result?.verdict ?? "nil") errorMessage=\(errorMessage ?? "nil")"
        + " isAnalyzing=\(isAnalyzing) recordingStartedAt=\(recordingStartedAt.map { "\($0)" } ?? "nil")"
        + " isRecording=\(recorder.isRecording) lastRecordingURL=\(recorder.lastRecordingURL?.lastPathComponent ?? "nil")"
        + " ratingPromptTask=\(ratingPromptTask == nil ? "nil" : "pending")"
        + " showSessionGate=\(showSessionGate) showPromoGate=\(showPromoGate) menuOpen=\(menuOpen)"
        + " menuDestination=\(menuDestination.map { "\($0)" } ?? "nil") showInviteSheet=\(showInviteSheet)"
        + " shareItem=\(shareItem == nil ? "nil" : "set")"
        + " | wallet versionCount=\(wallet.versionAnalyses) sessionUnlocked=\(wallet.sessionUnlocked)"
        + " canThump=\(wallet.canThump) needsPromoAd=\(wallet.needsPromoAd) needsSessionUnlock=\(wallet.needsSessionUnlock)"
    }
    #endif

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
            ResultView(result: result, errorMessage: errorMessage, onAgain: startNextMelon)
                .photographAction(resultRecordId.flatMap { id in
                    MelonRecordStore.shared.record(id: id) == nil ? nil : { showResultRecord = true }
                })
        } else {
            homeView
        }
    }

    /// FIX1/FIX2: a record's capture view in its own sheet, with the
    /// list's Done button; its "Thump this melon" closes the sheet and
    /// arms the record (thumpForRecord).
    private func recordSheet(_ id: UUID, close: @escaping () -> Void) -> some View {
        NavigationStack {
            RecordDetailView(recordId: id, onThump: {
                close()
                thumpForRecord(id)
            })
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l.t("common.done")) { close() }
                }
            }
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

            Text(l.t("home.journeyHint"))
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 10)

            creditsRow
                .padding(.top, 8)

            if let id = continuingRecordId, let record = MelonRecordStore.shared.record(id: id) {
                // 2.0: the next thump goes to this melon record.
                HStack(spacing: 6) {
                    Text(l.f("records.thumpingFor", record.createdAt.formatted(date: .abbreviated, time: .shortened)))
                    Button {
                        continuingRecordId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(l.t("common.cancel"))
                }
                .font(.caption)
                .foregroundColor(MelonTheme.inkSoft)
                .padding(.top, 6)
            }

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
        if wallet.adsSuppressed {
            // 2.0: owner-install adExempt or a permanently exempt contributor.
            Text(l.t("credits.adFree"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.isFreeDay {
            Text(l.t("credits.freeDay"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.nextThumpIsPromoFree {
            // Launch promo, this version's first thumps: no ad (2026-11-06).
            Text(wallet.promoFreeRemaining == 1
                 ? l.t("credits.promoFreeOne") : l.f("credits.promoFreeMany", wallet.promoFreeRemaining))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.deepGreen)
        } else if wallet.needsPromoAd {
            // Launch promo, past the free thumps (1.1.0 session gate).
            // FIX8: static wording — the 开始验瓜 button carries the gate.
            Text(l.t("credits.promoGate"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(MelonTheme.buttonGreen)
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
                continueJourneyAfterUnlock()
            } else {
                // FIX8: no completed ad, no unlock — the journey stops here.
                resumeJourneyAfterUnlock = false
                if !AdsManager.shared.rewardedReady {
                    errorMessage = l.t("ad.loading")
                }
            }
        }
    }

    /// 2.0: spends one contributor ad-free unit; on success the session
    /// unlocks exactly as a watched ad does.
    private func spendAdFreeUnit() {
        Task {
            switch await program.spendAdFreeUnit() {
            case .spent:
                wallet.unlockSessionWithAd()
                continueJourneyAfterUnlock()
            case .exempt:
                // permanent exemption now suppresses every gate
                continueJourneyAfterUnlock()
            case .failed:
                resumeJourneyAfterUnlock = false
                errorMessage = l.t("gate.adFreeFailed")
            }
        }
    }

    /// FIX8: after the promo gate unlocks the session, the 开始验瓜 tap
    /// that raised it carries on: record binding, photo gate, recording.
    private func continueJourneyAfterUnlock() {
        guard resumeJourneyAfterUnlock else { return }
        resumeJourneyAfterUnlock = false
        guard wallet.canThump, !recorder.isRecording, !isAnalyzing else { return }
        toggleRecording()
    }

    /// 2.0 "Thump this melon" from a record: back to the home flow with
    /// the record as the target, then the normal Start path (gates,
    /// credits and ads exactly as for any thump).
    private func thumpForRecord(_ id: UUID) {
        continuingRecordId = id
        menuDestination = nil
        result = nil
        Task {
            // Let the records sheet finish dismissing first.
            try? await Task.sleep(for: .milliseconds(600))
            if !recorder.isRecording && !isAnalyzing { toggleRecording() }
        }
    }

    // MARK: - Result → next melon (design doc 1.2.0 §2)

    /// "Thump Another Melon": one tap from the result straight back to
    /// the start-recording screen, with every piece of per-thump screen
    /// state reset — exactly as if the user had come back by hand.
    ///
    /// Deliberately touches NO session state: CreditWallet (per-version
    /// count, session unlock, promo/session gates) and AdsManager are
    /// not referenced here. The next thump goes through the normal
    /// Start button → toggleRecording → wallet.canThump check, and the
    /// count moves only when that next analysis completes
    /// (recordAnalysis). ios/Tools/next-melon/run.sh checks this
    /// function's body for exactly that.
    private func startNextMelon() {
        // The rating prompt belongs to the result being left.
        ratingPromptTask?.cancel()
        ratingPromptTask = nil
        // Defensive: the result screen is only shown when not recording.
        if recorder.isRecording { recorder.stopRecording() }
        // Drop the reference to the analyzed take (its archived copy in
        // Documents/Recordings stays — retention is by design).
        recorder.clearLastRecording()
        recordingStartedAt = nil
        isAnalyzing = false
        errorMessage = nil
        showSessionGate = false
        showPromoGate = false
        resumeJourneyAfterUnlock = false
        menuOpen = false
        menuDestination = nil
        showInviteSheet = false
        shareItem = nil
        // FIX1: the result's record link belongs to the result being left.
        showResultRecord = false
        resultRecordId = nil
        // 2.0: another melon — the next thump starts a new record.
        continuingRecordId = nil
        // Last: clearing the result switches content to homeView.
        result = nil
    }

    // MARK: - Actions (unchanged from v1)

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
            recordingStartedAt = nil
            analyze()
        } else {
            // FIX8 ad gate FIRST — 开始验瓜 is the gated action. Every
            // entry (home button, a record's "Thump this melon", the
            // home screen reached via "Thump Another Melon") comes
            // through here. Nothing is bound or opened until the session
            // is unlocked; on unlock the journey resumes by itself.
            if wallet.needsPromoAd {
                resumeJourneyAfterUnlock = true
                showPromoGate = true
                return
            }
            // FIX2 photo gate — on the recording-start path itself, so
            // every route (home tap, a record's "Thump this melon", an
            // armed target) passes it. Checked BEFORE the remaining wallet
            // gates (session unlock / credits): a refused start never
            // shows, spends or skips one; those are evaluated when
            // recording actually starts. (FIX8: the promo ad gate alone
            // now runs first, above.)
            guard let boundId = passPhotoGate() else { return }
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
                    gatedRecordId = boundId
                } catch {
                    errorMessage = l.f("error.startRecording", error.localizedDescription)
                }
            }
        }
    }

    /// FIX2: binds the start to its record exactly as filing will
    /// (armed target, else the open UNKNOWN-only home record, else a new
    /// record) and returns it when it has both appearance photos. If not,
    /// recording does not start: the record (created now for a new melon)
    /// is armed and its capture sheet opens on Step 1.
    private func passPhotoGate() -> UUID? {
        let store = MelonRecordStore.shared
        let id = store.boundRecordId(target: continuingRecordId) ?? store.createRecord(fromHomeThump: true).id
        if store.record(id: id)?.hasRequiredPhotos == true { return id }
        continuingRecordId = id
        menuDestination = nil
        photoGateRecordId = id
        return nil
    }

    /// FIX2: a gate-created record left without anything in it is
    /// removed again (no empty rows in My Melons); one with a photo stays
    /// armed so the next tap comes back to the same melon.
    private func photoGateDismissed() {
        guard let id = continuingRecordId, let record = MelonRecordStore.shared.record(id: id),
              record.isBlank else { return }
        MelonRecordStore.shared.delete(id)
        continuingRecordId = nil
    }

    private func analyze() {
        guard let audioURL = recorder.lastRecordingURL else {
            errorMessage = l.t("error.noRecording")
            return
        }
        isAnalyzing = true
        errorMessage = nil
        resultRecordId = nil
        // FIX2: file into the record the photo gate passed for this take.
        let target = gatedRecordId ?? continuingRecordId
        gatedRecordId = nil
        Task {
            defer { isAnalyzing = false }
            do {
                // Analysis runs fully on-device; nothing is uploaded.
                // The model is the one picked in the hamburger menu
                // (Baby 1.0 by default), effective from this analysis.
                let model = ModelRegistry.shared.activeModel
                let analyzed = try model.analyze(audioURL: audioURL)
                result = analyzed
                // 1.2.0 recording retention (design doc §6): keep this
                // exact input WAV + a metadata sidecar in
                // Documents/Recordings (newest 20). Local only — never
                // uploaded, excluded from backup.
                let d = model.descriptor
                // 2.0 melon record: file this thump into its record (the
                // chosen one, or a background home-flow record) and link
                // the archive copy once it is written — no second copy.
                let (recordId, thumpId) = MelonRecordStore.shared.attachThump(
                    analyzed, modelId: d.modelId, modelVersion: d.modelVersion, target: target)
                // FIX1: the result's "Photograph this melon" opens this record.
                resultRecordId = recordId
                RecordingArchive.save(.init(
                    sourceURL: audioURL, analyzedAt: Date(),
                    modelId: d.modelId, modelVersion: d.modelVersion,
                    modelDisplayName: d.displayName,
                    verdict: analyzed.verdict, confidence: analyzed.confidence,
                    dominantFrequencyHz: analyzed.dominantFrequencyHz,
                    spectralCentroidHz: analyzed.spectralCentroidHz,
                    decayTimeMs: analyzed.decayTimeMs,
                    analyzerLabel: analyzed.modelVersion,
                    debugSummary: analyzed.debugSummary)) { stem in
                    Task { @MainActor in MelonRecordStore.shared.linkRecording(stem: stem, thumpId: thumpId) }
                }
                // 1.2.0 allowance: every real (non-UNKNOWN) analysis
                // bumps this app version's count (promo freebies); in the
                // post-promotion economy the first one uses up the free
                // thump; it is also the invitee's
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
        ratingPromptTask?.cancel()
        ratingPromptTask = Task {
            try? await Task.sleep(for: .seconds(RatingPolicy.settleDelaySeconds))
            guard !Task.isCancelled, result?.verdict == Ripeness.ripe.rawValue, !isAnalyzing, !recorder.isRecording,
                  !menuOpen, menuDestination == nil, errorMessage == nil,
                  !showSessionGate, !showPromoGate, !showInviteSheet, shareItem == nil, !showResultRecord,
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

            // FIX9: the auto-stop hint (formerly home.hint) lives with
            // the recording instructions, at the active duration.
            Text(l.f("rec.thumpHint", durationSeconds))
                .font(.caption)
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
    /// FIX1: opens the melon record this thump was filed into (its Step 1
    /// is the appearance photos). nil = no record → no button.
    var onPhotograph: (() -> Void)? = nil

    /// Sets `onPhotograph` (a chained call, so the primary
    /// `ResultView(…, onAgain: startNextMelon)` wiring stays as it is).
    func photographAction(_ action: (() -> Void)?) -> ResultView {
        var view = self
        view.onPhotograph = action
        return view
    }

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

            // FIX1: the melon is in hand right now — photos one tap away.
            if let onPhotograph {
                Button(action: onPhotograph) {
                    Label(l.t("res.photograph"), systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(MelonTheme.cream)
                        .foregroundColor(MelonTheme.buttonGreen)
                        .cornerRadius(999)
                        .overlay(Capsule().stroke(MelonTheme.buttonGreen, lineWidth: 2))
                }
                .accessibilityIdentifier("result.photograph")
                .padding(.bottom, 12)
            }

            // The one-tap way back to the start-recording screen.
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
            .accessibilityIdentifier("result.nextMelon")
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
