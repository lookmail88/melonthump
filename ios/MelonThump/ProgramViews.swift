import SwiftUI

// MARK: - Model Improvement Program screens (design doc 2.0 §5 item 6)
//
// Settings → "Join the Model Improvement Program" → explanation page
// (privacy wording per §7 item 8) → enrollment note → application.
// Once applied the same entry opens the program home: status, ad-free
// balance, permanent exemption, My contributions. Every failure shows
// the calm "not available yet" state; nothing here can block thumping.

/// The Settings entry point: picks the right screen for the standing.
struct ProgramEntryView: View {
    @ObservedObject private var program = ContributorProgram.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        Group {
            switch program.phase {
            case .notEnrolled:
                ProgramExplanationView(showApply: true)
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ProgramUnavailableView { Task { await program.refresh() } }
            case .enrolled(let status):
                ProgramHomeView(status: status)
            }
        }
        .task { await program.refresh() }
    }
}

struct ProgramUnavailableView: View {
    let retry: () -> Void
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "leaf")
                        .font(.system(size: 34))
                        .foregroundColor(MelonTheme.buttonGreenAdaptive)
                    Text(l.t("program.unavailableTitle"))
                        .font(.headline)
                        .foregroundColor(MelonTheme.inkAdaptive)
                    Text(l.t("program.unavailable"))
                        .font(.subheadline)
                        .foregroundColor(MelonTheme.inkSoftAdaptive)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                Button(l.t("program.retry"), action: retry)
                    .foregroundColor(MelonTheme.buttonGreenAdaptive)
            }
        }
        .navigationTitle(l.t("program.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the program is, what it uploads, the privacy stance (§7 item 8,
/// the same wording as the App Store privacy label) and what it earns.
struct ProgramExplanationView: View {
    let showApply: Bool
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        List {
            Section {
                Text(l.t("program.intro"))
                    .foregroundColor(MelonTheme.inkAdaptive)
            }
            Section {
                bullet("camera.macro", l.t("program.part.appearance"))
                bullet("waveform", l.t("program.part.recording"))
                bullet("fork.knife", l.t("program.part.cutOpen"))
                bullet("star", l.t("program.part.feedback"))
            } header: {
                Text(l.t("program.partsHeader"))
            }
            Section {
                bullet("gift", l.t("program.earn"))
            } header: {
                Text(l.t("program.earnHeader"))
            }
            Section {
                bullet("arrow.up.doc", l.t("program.privacy.uploaded"))
                bullet("person.crop.circle.badge.questionmark", l.t("program.privacy.anonymous"))
                bullet("server.rack", l.t("program.privacy.storage"))
                bullet("hand.raised", l.t("program.privacy.label"))
                bullet("trash", l.t("program.privacy.delete"))
                bullet("iphone", l.t("program.privacy.ordinary"))
            } header: {
                Text(l.t("program.privacyHeader"))
            }
            Section {
                bullet("checkmark.seal", l.t("program.approval"))
            }
            if showApply {
                Section {
                    NavigationLink {
                        ProgramApplyView()
                    } label: {
                        Text(l.t("program.continue"))
                            .font(.headline)
                            .foregroundColor(MelonTheme.buttonGreenAdaptive)
                    }
                    .accessibilityIdentifier("program.continue")
                }
            }
        }
        .navigationTitle(l.t("program.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(MelonTheme.buttonGreenAdaptive)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(MelonTheme.inkAdaptive)
        }
    }
}

/// The enrollment note (required) and the application submission.
struct ProgramApplyView: View {
    @ObservedObject private var program = ContributorProgram.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var busy = false
    @State private var message: String?
    private var l: L10n { L10n(preference: languagePref) }

    private var canSubmit: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $note)
                    .frame(minHeight: 120)
                    .onChange(of: note) { _, text in
                        if text.count > 1000 { note = String(text.prefix(1000)) }
                    }
                    .accessibilityIdentifier("program.note")
            } header: {
                Text(l.t("program.noteHeader"))
            } footer: {
                Text(l.t("program.noteFooter"))
            }
            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Text(l.t("program.submit")).font(.headline)
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("program.submit")
            }
        }
        .navigationTitle(l.t("program.applyTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(l.t("common.ok"), role: .cancel) { message = nil }
        }
    }

    private func submit() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await program.apply(note: note)
                dismiss()
            } catch let e as ContributionError {
                message = ProgramErrorText.text(e, l)
            } catch {
                message = l.t("program.unavailable")
            }
        }
    }
}

/// Program home: application status, ad-free balance, exemption.
struct ProgramHomeView: View {
    let status: ContributorStatus
    @ObservedObject private var program = ContributorProgram.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(l.t("program.status"))
                    Spacer()
                    Text(statusText).foregroundColor(.secondary)
                }
                Text(statusDetail)
                    .font(.footnote)
                    .foregroundColor(MelonTheme.inkSoftAdaptive)
            }
            if status == .approved || program.adFreeBalance > 0 || program.adExemptPermanent {
                Section {
                    if program.adExemptPermanent {
                        HStack {
                            Image(systemName: "sparkles").foregroundColor(MelonTheme.buttonGreenAdaptive)
                            Text(l.t("program.exempt"))
                        }
                    } else {
                        HStack {
                            Text(l.t("program.balance"))
                            Spacer()
                            Text("\(program.adFreeBalance)").font(.headline.monospacedDigit())
                        }
                    }
                } header: {
                    Text(l.t("program.adFreeHeader"))
                } footer: {
                    Text(program.adExemptPermanent ? l.t("program.exemptFooter") : l.t("program.balanceFooter"))
                }
            }
            Section {
                NavigationLink {
                    MyContributionsView()
                } label: {
                    Label(l.t("program.myContributions"), systemImage: "tray.full")
                }
                if status == .approved {
                    Text(l.t("program.howToContribute"))
                        .font(.footnote)
                        .foregroundColor(MelonTheme.inkSoftAdaptive)
                }
            }
            Section {
                NavigationLink {
                    ProgramExplanationView(showApply: false)
                } label: {
                    Label(l.t("program.about"), systemImage: "info.circle")
                }
            } footer: {
                if let id = program.contributorId {
                    Text(l.f("program.idFooter", String(id.uuidString.lowercased().prefix(8))))
                }
            }
        }
        .navigationTitle(l.t("program.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await program.refresh() }
    }

    private var statusText: String {
        switch status {
        case .pending: return l.t("program.pending")
        case .approved: return l.t("program.approved")
        case .declined: return l.t("program.declined")
        case .revoked: return l.t("program.revoked")
        }
    }

    private var statusDetail: String {
        switch status {
        case .pending: return l.t("program.pendingDetail")
        case .approved: return l.t("program.approvedDetail")
        case .declined: return l.t("program.declinedDetail")
        case .revoked: return l.t("program.revokedDetail")
        }
    }
}

/// Self-service: own samples with status, completeness, return reason,
/// and withdrawal (true deletion of the server copies).
struct MyContributionsView: View {
    @ObservedObject private var program = ContributorProgram.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @State private var pendingWithdraw: SampleSummary?
    @State private var message: String?
    @State private var loaded = false
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        List {
            if program.samplesUnavailable {
                Section {
                    Text(l.t("program.unavailable"))
                        .font(.subheadline)
                        .foregroundColor(MelonTheme.inkSoftAdaptive)
                }
            } else if loaded && program.samples.isEmpty {
                Section {
                    Text(l.t("contrib.none"))
                        .font(.subheadline)
                        .foregroundColor(MelonTheme.inkSoftAdaptive)
                }
            }
            ForEach(program.samples) { sample in
                Section {
                    HStack {
                        Text(l.f("contrib.sampleNumber", String(sample.id))).font(.headline)
                        Spacer()
                        Text(SampleStatusText.text(sample.status, l)).foregroundColor(.secondary)
                    }
                    if let v = sample.variety.flatMap(MelonVariety.init(rawValue:)) {
                        Text(v.displayName(l)).font(.caption).foregroundColor(MelonTheme.inkSoftAdaptive)
                    }
                    HStack(spacing: 10) {
                        part(l.t("part.appearance"), sample.completeness.appearance)
                        part(l.t("part.recording"), sample.completeness.recording)
                        part(l.t("part.cutOpen"), sample.completeness.cutOpen)
                        part(l.t("part.feedback"), sample.completeness.feedback)
                    }
                    .font(.caption)
                    Text(sample.complete ? l.t("contrib.complete") : l.t("contrib.incomplete"))
                        .font(.caption)
                        .foregroundColor(sample.complete ? MelonTheme.buttonGreenAdaptive : .secondary)
                    if sample.status == "RETURNED", let reason = sample.returnReason {
                        Text(l.f("contrib.returnReason", reason))
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                    if sample.status == "SUBMITTED" || sample.status == "RETURNED" {
                        Button(l.t("contrib.withdraw"), role: .destructive) { pendingWithdraw = sample }
                    }
                }
            }
        }
        .navigationTitle(l.t("program.myContributions"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await program.loadSamples()
            loaded = true
        }
        .refreshable { await program.loadSamples() }
        .confirmationDialog(l.t("contrib.withdrawTitle"), isPresented: Binding(
            get: { pendingWithdraw != nil }, set: { if !$0 { pendingWithdraw = nil } }
        ), titleVisibility: .visible, presenting: pendingWithdraw) { sample in
            Button(l.t("contrib.withdraw"), role: .destructive) {
                Task {
                    do {
                        try await program.withdraw(sample.id)
                    } catch let e as ContributionError {
                        message = ProgramErrorText.text(e, l)
                    } catch {
                        message = l.t("program.unavailable")
                    }
                }
            }
            Button(l.t("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(l.t("contrib.withdrawMessage"))
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(l.t("common.ok"), role: .cancel) { message = nil }
        }
    }

    private func part(_ title: String, _ present: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: present ? "checkmark.circle.fill" : "circle")
                .foregroundColor(present ? MelonTheme.buttonGreenAdaptive : .secondary)
            Text(title).foregroundColor(present ? .primary : .secondary)
        }
    }
}
