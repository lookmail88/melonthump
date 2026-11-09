import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - My Melons: the record list (thump history)

/// Every melon record, newest first. Tapping one reopens it; "+" starts
/// a new record for the unified capture flow. `onThump` hands a record
/// back to the home screen to record a thump for it with the existing
/// recording + analysis flow (gates, ads and credits unchanged).
struct RecordsListView: View {
    let onThump: (UUID) -> Void
    @ObservedObject private var store = MelonRecordStore.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []
    @State private var pendingDelete: MelonRecord?
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.records.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image("HeroMelon").resizable().scaledToFit().frame(width: 120)
                            Text(l.t("records.empty"))
                                .font(.subheadline)
                                .foregroundColor(MelonTheme.inkSoftAdaptive)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                ForEach(store.records) { record in
                    NavigationLink(value: record.id) {
                        RecordRow(record: record)
                    }
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = record } label: {
                            Label(l.t("records.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(l.t("records.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                RecordDetailView(recordId: id, onThump: { thump(id) })
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l.t("common.done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        path.append(store.createRecord().id)
                    } label: {
                        Label(l.t("records.new"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("records.new")
                }
            }
            .alert(l.t("records.deleteTitle"), isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { record in
                Button(l.t("records.delete"), role: .destructive) { store.delete(record.id) }
                Button(l.t("common.cancel"), role: .cancel) {}
            } message: { record in
                Text(record.submission != nil && record.submission?.serverStatus != "WITHDRAWN"
                     ? l.t("records.deleteSubmitted") : l.t("records.deleteMessage"))
            }
        }
    }

    private func thump(_ id: UUID) {
        dismiss()
        onThump(id)
    }
}

struct RecordRow: View {
    let record: MelonRecord
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        HStack(spacing: 12) {
            RecordThumbnail(recordId: record.id, photo: record.thumbnailPhoto)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                    .foregroundColor(MelonTheme.inkAdaptive)
                Text(record.variety?.displayName(l) ?? l.t("records.noVariety"))
                    .font(.caption)
                    .foregroundColor(MelonTheme.inkSoftAdaptive)
                if let verdict = record.verdict {
                    let r = Ripeness(verdict: verdict)
                    Text("\(r.emoji) \(r.displayName(l))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(MelonTheme.inkAdaptive)
                } else {
                    Text(l.t("records.noThump"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if record.submission != nil, record.submission?.serverStatus != "WITHDRAWN" {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(MelonTheme.buttonGreenAdaptive)
                    .accessibilityLabel(l.t("records.contributed"))
            }
        }
    }
}

/// First appearance photo, or Stephanie's hero melon when there is none.
struct RecordThumbnail: View {
    let recordId: UUID
    let photo: RecordPhoto?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                MelonTheme.background
                Image("HeroMelon").resizable().scaledToFit().padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: photo?.id) {
            guard let photo else { image = nil; return }
            let url = MelonRecordStore.shared.url(of: photo, in: recordId)
            image = await Task.detached(priority: .utility) { RecordImage.thumbnail(at: url) }.value
        }
    }
}

// MARK: - One record: the unified capture flow

/// Everyone sees 1 appearance photos and 2 thump. Program members
/// (PENDING or APPROVED, `ContributorProgram.isMember`) also see the
/// steps that feed the model: 3 weight (optional), 4 variety (selection
/// only) and, after eating, the cut-open photo and the user's own
/// feedback (FIX6). Display gating only — stored weight / variety /
/// cut-open / feedback are never touched, and reappear on joining.
/// Approved contributors additionally see "Contribute this melon".
/// No model score anywhere (design §6 gates).
struct RecordDetailView: View {
    let recordId: UUID
    let onThump: () -> Void
    @ObservedObject private var store = MelonRecordStore.shared
    @ObservedObject private var program = ContributorProgram.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var showFeedbackEditor = false
    @State private var confirmContribute = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false
    @FocusState private var weightFocused: Bool
    private var l: L10n { L10n(preference: languagePref) }

    private var record: MelonRecord? { store.record(id: recordId) }

    var body: some View {
        Group {
            if let record {
                form(record)
            } else {
                Text(l.t("records.gone")).foregroundColor(.secondary)
            }
        }
        .navigationTitle(record?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let w = record?.weightGrams { weightText = String(w) }
        }
        .task {
            if let record, record.submission != nil { await program.refreshSample(of: record) }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(l.t("common.ok"), role: .cancel) { message = nil }
        }
        .sheet(isPresented: $showFeedbackEditor) {
            if let record {
                FeedbackEditor(initial: record.feedback) { feedback in
                    store.update(recordId) { $0.feedback = feedback }
                }
            }
        }
    }

    @ViewBuilder
    private func form(_ record: MelonRecord) -> some View {
        List {
            // 1. Appearance photos
            Section {
                if !record.hasRequiredPhotos {
                    // FIX2: photos first — the thump stays locked until
                    // one appearance photo (rind or whole melon) is in.
                    Label(l.t("capture.photosFirst"), systemImage: "camera.badge.ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(MelonTheme.inkAdaptive)
                        .accessibilityIdentifier("record.photosFirst")
                }
                PhotoStrip(recordId: recordId, photos: record.photos) { photo in
                    store.removePhoto(photo, from: recordId)
                }
                PhotoAddButton(title: l.t("capture.addRind"), systemImage: "camera.macro",
                               scanKind: .rindCloseUp) { data, type in
                    save(data, type, kind: .rindCloseUp)
                }
                PhotoAddButton(title: l.t("capture.addWhole"), systemImage: "camera",
                               guidance: l.t("capture.cardGuide"), scanKind: .wholeMelon) { data, type in
                    save(data, type, kind: .wholeMelon)
                }
            } header: {
                Text(l.t("capture.step1"))
            } footer: {
                Text(l.t("capture.photosFooter"))
            }

            // 2. Thump
            Section {
                ForEach(record.thumps) { thump in
                    ThumpRow(thump: thump)
                }
                Button {
                    onThump()
                } label: {
                    Label(record.thumps.isEmpty ? l.t("capture.thump") : l.t("capture.thumpMore"),
                          systemImage: "waveform")
                        .foregroundColor(MelonTheme.buttonGreenAdaptive)
                }
                // FIX2: locked (dimmed) until one appearance photo exists;
                // enables the moment it is saved.
                .disabled(!record.hasRequiredPhotos)
                .opacity(record.hasRequiredPhotos ? 1 : 0.4)
                .accessibilityIdentifier("record.thump")
            } header: {
                Text(l.t("capture.step2"))
            } footer: {
                Text(l.t("capture.thumpFooter"))
            }

            // FIX6: steps 3–4 and the after-cutting section are for
            // program members only (display only; data stays on disk).
            if program.isMember {
                memberSteps(record)
            }

            // FIX7: PENDING applicants also see the section, with the
            // submit button locked until approval.
            if program.isApproved || program.isPending || record.submission != nil {
                contributeSection(record)
            }

            Section {
                Button(l.t("records.delete"), role: .destructive) { confirmDelete = true }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(l.t("common.done")) { weightFocused = false }
            }
        }
        .onChange(of: program.isMember) { _, member in
            // Standing flipped mid-session (e.g. REVOKED): drop focus and
            // the editor sheet for sections no longer shown. Nothing stored
            // is changed.
            if !member {
                weightFocused = false
                showFeedbackEditor = false
            }
        }
        .confirmationDialog(l.t("records.deleteTitle"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(l.t("records.delete"), role: .destructive) {
                store.delete(recordId)
                dismiss()
            }
        } message: {
            Text(record.submission != nil && record.submission?.serverStatus != "WITHDRAWN"
                 ? l.t("records.deleteSubmitted") : l.t("records.deleteMessage"))
        }
    }

    // MARK: Member-only steps (program members: PENDING / APPROVED)

    @ViewBuilder
    private func memberSteps(_ record: MelonRecord) -> some View {
        // 3. Weight (optional, never required)
        Section {
            HStack {
                TextField(l.t("weight.placeholder"), text: $weightText)
                    .keyboardType(.numberPad)
                    .focused($weightFocused)
                    .onChange(of: weightText) { _, text in commitWeight(text) }
                Text("g").foregroundColor(.secondary)
            }
            if record.weightProvenance == .photoEstimated {
                Text(WeightProvenance.photoEstimated.displayName(l)).foregroundColor(.secondary)
            } else {
                Picker(l.t("weight.how"), selection: Binding(
                    get: { record.weightProvenance ?? .scaleMeasured },
                    set: { p in store.update(recordId) { $0.weightProvenance = $0.weightGrams == nil ? nil : p } }
                )) {
                    Text(WeightProvenance.scaleMeasured.displayName(l)).tag(WeightProvenance.scaleMeasured)
                    Text(WeightProvenance.manualEstimate.displayName(l)).tag(WeightProvenance.manualEstimate)
                }
                .pickerStyle(.segmented)
                .disabled(record.weightGrams == nil)
            }
        } header: {
            Text(l.t("capture.step3"))
        } footer: {
            Text(l.t("weight.footer"))
        }

        // 4. Variety (selection only, never free text)
        Section {
            Picker(l.t("variety.title"), selection: Binding(
                get: { record.variety },
                set: { v in store.update(recordId) { $0.variety = v } }
            )) {
                Text(l.t("variety.unset")).tag(MelonVariety?.none)
                ForEach(MelonVariety.allCases) { v in
                    Text(v.displayName(l)).tag(MelonVariety?.some(v))
                }
            }
        } header: {
            Text(l.t("capture.step4"))
        }

        // After eating: cut-open photo + the user's own feedback
        Section {
            if let cut = record.cutOpenPhoto {
                PhotoStrip(recordId: recordId, photos: [cut]) { photo in
                    store.removePhoto(photo, from: recordId)
                }
            }
            PhotoAddButton(title: record.cutOpenPhoto == nil ? l.t("capture.addCut") : l.t("capture.replaceCut"),
                           systemImage: "fork.knife") { data, type in
                save(data, type, kind: .cutOpen)
            }
            if let fb = record.feedback {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.f("feedback.scoreLine", fb.score))
                        .font(.headline)
                        .foregroundColor(MelonTheme.inkAdaptive)
                    Text(fb.bandTruth.displayName(l))
                        .font(.subheadline)
                        .foregroundColor(MelonTheme.inkSoftAdaptive)
                    if !fb.tasteTags.isEmpty {
                        Text(fb.tasteTags.map { $0.displayName(l) }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(MelonTheme.inkSoftAdaptive)
                    }
                }
            }
            Button(record.feedback == nil ? l.t("feedback.add") : l.t("feedback.edit")) {
                showFeedbackEditor = true
            }
            .foregroundColor(MelonTheme.buttonGreenAdaptive)
        } header: {
            Text(l.t("capture.afterEating"))
        } footer: {
            Text(l.t("feedback.footer"))
        }
    }

    // MARK: Contribute (approved contributors; locked for pending applicants)

    @ViewBuilder
    private func contributeSection(_ record: MelonRecord) -> some View {
        Section {
            PackageChecklist(record: record)
            if let sub = record.submission {
                HStack {
                    Text(l.f("contrib.sampleNumber", String(sub.sampleId)))
                    Spacer()
                    Text(SampleStatusText.text(sub.serverStatus, l)).foregroundColor(.secondary)
                }
                if sub.serverStatus == "RETURNED", let reason = sub.returnReason {
                    Text(l.f("contrib.returnReason", reason))
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
                if ["SUBMITTED", "RETURNED"].contains(sub.serverStatus), program.isApproved,
                   ContributorProgram.hasPendingAppend(record) {
                    Button {
                        run { try await program.appendUpdates(record) }
                    } label: {
                        busyLabel(l.t("contrib.sendUpdates"), icon: "arrow.up.circle")
                    }
                    .disabled(busy)
                }
            } else if !program.isApproved {
                // FIX7B: pending applicant — the button is visible but
                // disabled for the whole review period, whatever the local
                // state. The footer caption explains why; nothing happens on tap.
                Button {} label: {
                    HStack {
                        Label(l.t("contrib.contribute"), systemImage: "icloud.and.arrow.up")
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "lock.fill").foregroundColor(.secondary)
                    }
                }
                .disabled(true)
                .accessibilityIdentifier("record.contribute.locked")
                .accessibilityHint(l.t("contrib.lockedUntilApproved"))
            } else {
                Button {
                    confirmContribute = true
                } label: {
                    busyLabel(l.t("contrib.contribute"), icon: "icloud.and.arrow.up")
                }
                .disabled(busy || record.variety == nil)
                .confirmationDialog(l.t("contrib.contribute"), isPresented: $confirmContribute, titleVisibility: .visible) {
                    Button(l.t("contrib.upload")) {
                        run { try await program.submit(record) }
                    }
                    Button(l.t("common.cancel"), role: .cancel) {}
                } message: {
                    Text(l.t("contrib.confirm"))
                }
            }
        } header: {
            Text(l.t("contrib.section"))
        } footer: {
            if record.submission == nil, !program.isApproved {
                Label(l.t("contrib.lockedUntilApproved"), systemImage: "lock.fill")
            } else if record.submission == nil {
                Text(record.variety == nil ? l.t("contrib.needVariety") : l.t("contrib.footer"))
            } else if program.isMember {
                // FIX6: the append footer points at the cut-open photo and
                // rating, which non-members don't see.
                Text(l.t("contrib.appendFooter"))
            }
        }
    }

    private func busyLabel(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundColor(MelonTheme.buttonGreenAdaptive)
            Spacer()
            if busy { ProgressView() }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await work()
                message = l.t("contrib.sent")
            } catch let e as ContributionError {
                message = ProgramErrorText.text(e, l)
            } catch {
                message = l.t("program.unavailable")
            }
        }
    }

    // MARK: Helpers

    private func save(_ data: Data, _ contentType: String, kind: PhotoKind) {
        do {
            try store.addPhoto(data, contentType: contentType, kind: kind, to: recordId)
        } catch {
            message = l.t("capture.saveFailed")
        }
    }

    private func commitWeight(_ text: String) {
        let digits = text.filter(\.isNumber)
        if digits != text { weightText = digits; return }
        let grams = Int(digits.prefix(6)).flatMap { $0 > 0 ? $0 : nil }
        store.update(recordId) { r in
            r.weightGrams = grams
            if grams == nil {
                r.weightProvenance = nil
            } else if r.weightProvenance == nil || r.weightProvenance == .photoEstimated {
                r.weightProvenance = .scaleMeasured
            }
        }
    }
}

struct ThumpRow: View {
    let thump: RecordThump
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        let r = Ripeness(verdict: thump.verdict)
        HStack {
            Text(r.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.displayName(l)).foregroundColor(MelonTheme.inkAdaptive)
                Text(thump.analyzedAt.formatted(date: .omitted, time: .shortened)
                     + (r == .unknown ? "" : String(format: " · %.0f Hz", thump.dominantFrequencyHz)))
                    .font(.caption)
                    .foregroundColor(MelonTheme.inkSoftAdaptive)
            }
            Spacer()
            if thump.archiveStem != nil, thump.recordingURL == nil {
                Text(l.t("capture.recordingGone")).font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

/// Which of the four sample parts this record holds.
struct PackageChecklist: View {
    let record: MelonRecord
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        HStack(spacing: 10) {
            item(l.t("part.appearance"), !record.photos.isEmpty)
            item(l.t("part.recording"), record.contributableThump != nil)
            item(l.t("part.cutOpen"), record.cutOpenPhoto != nil)
            item(l.t("part.feedback"), record.feedback != nil)
        }
        .font(.caption)
    }

    private func item(_ title: String, _ present: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: present ? "checkmark.circle.fill" : "circle")
                .foregroundColor(present ? MelonTheme.buttonGreenAdaptive : .secondary)
            Text(title).foregroundColor(present ? .primary : .secondary)
        }
    }
}

// MARK: - Photos

struct PhotoStrip: View {
    let recordId: UUID
    let photos: [RecordPhoto]
    let onDelete: (RecordPhoto) -> Void
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        VStack(spacing: 3) {
                            RecordThumbnail(recordId: recordId, photo: photo)
                                .frame(width: 76, height: 76)
                            Text(label(photo.kind)).font(.caption2).foregroundColor(.secondary)
                        }
                        .contextMenu {
                            Button(role: .destructive) { onDelete(photo) } label: {
                                Label(l.t("capture.removePhoto"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func label(_ kind: PhotoKind) -> String {
        switch kind {
        case .rindCloseUp: return l.t("capture.rind")
        case .wholeMelon: return l.t("capture.whole")
        case .cutOpen: return l.t("capture.cut")
        }
    }
}

/// "Take photo" (camera) or "Choose from library". Camera shots are
/// stored as full-resolution JPEG; library picks keep their original
/// bytes when the server accepts the format, else a JPEG re-encode.
struct PhotoAddButton: View {
    let title: String
    let systemImage: String
    var guidance: String?
    /// FIX11: appearance photos (Step 1) shoot with the scan-style camera
    /// framed for this kind; nil (cut-open) keeps the system camera.
    var scanKind: PhotoKind?
    let onPhoto: (Data, String) -> Void
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showChoice = false
    @State private var libraryItem: PhotosPickerItem?
    private var l: L10n { L10n(preference: languagePref) }

    static let acceptedTypes = PhotoCapture.acceptedTypes

    var body: some View {
        Button {
            showChoice = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: systemImage).foregroundColor(MelonTheme.buttonGreenAdaptive)
                if let guidance {
                    Text(guidance).font(.caption).foregroundColor(MelonTheme.inkSoftAdaptive)
                }
            }
        }
        .confirmationDialog(title, isPresented: $showChoice, titleVisibility: guidance == nil ? .hidden : .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(l.t("capture.camera")) { showCamera = true }
            }
            Button(l.t("capture.library")) { showLibrary = true }
            Button(l.t("common.cancel"), role: .cancel) {}
        } message: {
            if let guidance { Text(guidance) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            if let scanKind {
                ScanCameraView(kind: .constant(scanKind), onPhoto: onPhoto)
            } else {
                CameraPicker { image in
                    if let data = PhotoCapture.cameraJPEG(image) {
                        onPhoto(data, "image/jpeg")
                    }
                }
                .ignoresSafeArea()
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task {
                if let (data, mime) = await PhotoCapture.libraryPhoto(item) { onPhoto(data, mime) }
            }
        }
    }
}

/// The capture encoding shared by PhotoAddButton (record page) and
/// JourneyPhotoSheet (FIX10 journey gate): camera shots become
/// full-resolution JPEG; library picks keep their original bytes when
/// the server accepts the format, else a full-quality JPEG re-encode.
/// Both callers then store through MelonRecordStore.addPhoto — one path.
enum PhotoCapture {
    static let acceptedTypes = ["image/jpeg", "image/png", "image/heic", "image/heif", "image/webp"]

    static func cameraJPEG(_ image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 1.0)
    }

    static func libraryPhoto(_ item: PhotosPickerItem) async -> (Data, String)? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let mime = item.supportedContentTypes.first?.preferredMIMEType?.lowercased()
        if let mime, acceptedTypes.contains(mime) { return (data, mime) }
        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 1.0) {
            return (jpeg, "image/jpeg")
        }
        return nil
    }
}

// MARK: - FIX10: the journey's photo gate (camera first, then recording)

/// Opened by 开始验瓜 when the bound record has no appearance photo yet.
/// Not the record page: just the camera (opened on appear), a rind /
/// whole-melon choice (rind by default; whole shows the bank-card
/// guidance) and a library fallback. ONE photo of either kind passes
/// the FIX2 gate. `onSaved` fires once the photo is stored in the record
/// and any camera / picker UI has gone, so the caller can dismiss and
/// carry the journey on into recording; `onCancel` aborts the journey.
struct JourneyPhotoSheet: View {
    let recordId: UUID
    let onSaved: () -> Void
    let onCancel: () -> Void
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @State private var kind: PhotoKind = .rindCloseUp
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var cameraOpenedOnAppear = false
    @State private var saved = false
    @State private var saving = false
    @State private var message: String?
    private var l: L10n { L10n(preference: languagePref) }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(l.t("capture.photosFirst"), systemImage: "camera.badge.ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(MelonTheme.inkAdaptive)
                    Picker(l.t("capture.step1"), selection: $kind) {
                        Text(l.t("capture.kindRind")).tag(PhotoKind.rindCloseUp)
                        Text(l.t("capture.kindWhole")).tag(PhotoKind.wholeMelon)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("journeyPhoto.kind")
                    if kind == .wholeMelon {
                        Text(l.t("capture.cardGuide"))
                            .font(.caption)
                            .foregroundColor(MelonTheme.inkSoftAdaptive)
                    }
                }
                Section {
                    if cameraAvailable {
                        Button { showCamera = true } label: {
                            Label(l.t("capture.camera"), systemImage: kind == .rindCloseUp ? "camera.macro" : "camera")
                                .foregroundColor(MelonTheme.buttonGreenAdaptive)
                        }
                        .accessibilityIdentifier("journeyPhoto.camera")
                    }
                    Button { showLibrary = true } label: {
                        Label(l.t("capture.library"), systemImage: "photo.on.rectangle")
                            .foregroundColor(MelonTheme.buttonGreenAdaptive)
                    }
                    .accessibilityIdentifier("journeyPhoto.library")
                }
                .disabled(saving || saved)
            }
            .navigationTitle(l.t("capture.step1"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l.t("common.cancel")) { onCancel() }
                }
            }
        }
        .interactiveDismissDisabled(saving)
        .onAppear {
            // Camera first: the journey goes straight to the viewfinder.
            guard !cameraOpenedOnAppear else { return }
            cameraOpenedOnAppear = true
            if cameraAvailable { showCamera = true }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: finishIfSaved) {
            // FIX11: the scan-style camera, framed by (and able to switch)
            // this sheet's kind; its library button saves through the
            // same path, and its dismissal hands on via finishIfSaved.
            ScanCameraView(kind: $kind, allowsKindSwitch: true) { data, type in
                save(data, type)
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            saving = true
            Task {
                defer { saving = false }
                // Library picks count for the gate, exactly as on the record page.
                if let (data, mime) = await PhotoCapture.libraryPhoto(item) { save(data, mime) }
                finishIfSaved()
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(l.t("common.ok"), role: .cancel) { message = nil }
        }
    }

    /// The same storage path as the record page (RecordDetailView.save).
    private func save(_ data: Data, _ contentType: String) {
        do {
            try MelonRecordStore.shared.addPhoto(data, contentType: contentType, kind: kind, to: recordId)
            saved = true
        } catch {
            message = l.t("capture.saveFailed")
        }
    }

    /// Hands back only once the camera / picker is gone, so the sheet's
    /// own dismissal never races another presentation.
    private func finishIfSaved() {
        guard saved, !showCamera, !showLibrary else { return }
        onSaved()
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Feedback (the user's own score — not a model score)

struct FeedbackEditor: View {
    let initial: MelonFeedback?
    let onSave: (MelonFeedback) -> Void
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @Environment(\.dismiss) private var dismiss
    @State private var score: Double = 70
    @State private var tags: Set<TasteTag> = []
    @State private var band: BandTruth?
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(l.t("feedback.score"))
                        Spacer()
                        Text("\(Int(score))").font(.headline.monospacedDigit())
                    }
                    Slider(value: $score, in: 0...100, step: 1)
                        .tint(MelonTheme.buttonGreenAdaptive)
                } footer: {
                    Text(l.t("feedback.scoreFooter"))
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(TasteTag.allCases) { tag in
                            let on = tags.contains(tag)
                            Button {
                                if on { tags.remove(tag) } else { tags.insert(tag) }
                            } label: {
                                Text(tag.displayName(l))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(on ? MelonTheme.buttonGreen : Color.secondary.opacity(0.12))
                                    .foregroundColor(on ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(l.t("feedback.taste"))
                }
                Section {
                    Picker(l.t("feedback.band"), selection: $band) {
                        ForEach(BandTruth.allCases) { b in
                            Text(b.displayName(l)).tag(BandTruth?.some(b))
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(l.t("feedback.band"))
                } footer: {
                    Text(l.t("feedback.bandFooter"))
                }
            }
            .navigationTitle(l.t("feedback.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l.t("feedback.save")) {
                        if let band {
                            onSave(MelonFeedback(score: Int(score),
                                                 tasteTags: TasteTag.allCases.filter { tags.contains($0) },
                                                 bandTruth: band))
                        }
                        dismiss()
                    }
                    .disabled(band == nil)
                }
            }
            .onAppear {
                if let initial {
                    score = Double(initial.score)
                    tags = Set(initial.tasteTags)
                    band = initial.bandTruth
                }
            }
        }
    }
}

// MARK: - Shared text

enum SampleStatusText {
    static func text(_ status: String, _ l: L10n) -> String {
        switch status {
        case "SUBMITTED": return l.t("sample.submitted")
        case "APPROVED": return l.t("sample.approved")
        case "RETURNED": return l.t("sample.returned")
        case "VOIDED": return l.t("sample.voided")
        case "WITHDRAWN": return l.t("sample.withdrawn")
        default: return status
        }
    }
}

enum ProgramErrorText {
    static func text(_ e: ContributionError, _ l: L10n) -> String {
        switch e {
        case .unavailable: return l.t("program.unavailable")
        case .notApproved: return l.t("program.notApproved")
        case .unknownContributor: return l.t("program.unknown")
        case .tooLarge: return l.t("program.tooLarge")
        case .illegalState: return l.t("program.illegalState")
        case .rejected: return l.t("program.rejected")
        }
    }
}
