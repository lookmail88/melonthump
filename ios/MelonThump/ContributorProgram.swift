import Foundation
import Security

// MARK: - Model Improvement Program, client side (design doc 2.0 §5 item 6,
// §7 items 8–10)
//
// Fail-soft throughout: these endpoints do not exist on the currently
// shipped server. Every 404 / transport error / attestation failure
// ends in a calm "not available yet" state and never touches thumping,
// melon records or the ad / credit flows (same philosophy as VersionGate).

/// The anonymous contributor UUID: generated on-device when the user
/// submits an application and kept in the Keychain, so it survives a
/// reinstall on the same device. Deliberately separate from the stats
/// installId (UserDefaults, resets on uninstall).
enum ContributorIdentity {
    private static let service = "dev.xuyang.melonthump.contributor"
    private static let account = "contributorId"

    static var existing: UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: raw)
    }

    /// The stored id, or a new one written to the Keychain. nil only if
    /// the Keychain write fails.
    static func obtain() -> UUID? {
        if let existing { return existing }
        let id = UUID()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(id.uuidString.lowercased().utf8),
            // Device-only (no iCloud Keychain sync): one anonymous id per device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { return existing }
        return status == errSecSuccess ? id : nil
    }
}

// MARK: - Wire shapes

enum ContributorStatus: String, Codable, Sendable {
    case pending = "PENDING", approved = "APPROVED", declined = "DECLINED", revoked = "REVOKED"
}

struct ContributorStanding: Codable, Equatable, Sendable {
    let contributorId: UUID
    let status: String
    let adFreeBalance: Int
    let adExemptPermanent: Bool?

    var parsedStatus: ContributorStatus? { ContributorStatus(rawValue: status) }
}

struct SampleCompleteness: Codable, Equatable, Sendable {
    let appearance: Bool
    let recording: Bool
    let cutOpen: Bool
    let feedback: Bool
}

struct SampleSummary: Codable, Identifiable, Equatable, Sendable {
    let id: Int64
    let status: String
    let completeness: SampleCompleteness
    let complete: Bool
    let returnReason: String?
    let variety: String?
    let createdAt: String?
    let updatedAt: String?
}

struct SpendResult: Codable, Sendable {
    let spent: Bool
    let exempt: Bool
    let balance: Int
}

private struct ErrorBody: Decodable { let error: String? }

enum ContributionError: Error, Equatable {
    /// Endpoint missing (older server), offline, attestation impossible,
    /// or any unexpected answer: shown as "not available yet".
    case unavailable
    case notApproved
    case unknownContributor
    case tooLarge
    case illegalState
    case rejected(String)
}

// MARK: - Attested client

struct ContributionClient: Sendable {
    let environment: ServerEnvironment

    static let base = "/api/v1/contributions"

    private func headers(payload: Data) async throws -> [String: String] {
        _ = await AttestManager.shared.ensureEnrolled(environment: environment, installId: StatsReporter.installId)
        if let h = await AttestManager.shared.assertionHeaders(environment: environment, payload: payload) {
            return h
        }
        // Simulator: no App Attest; only the dev backend honours the bypass.
        if !AttestManager.isSupported { return AttestManager.bypassHeaders }
        throw ContributionError.unavailable
    }

    private func url(path: String, rawQuery: String? = nil) throws -> URL {
        var s = environment.baseURL.absoluteString
        if s.hasSuffix("/") { s.removeLast() }
        s += path
        if let rawQuery, !rawQuery.isEmpty { s += "?" + rawQuery }
        guard let url = URL(string: s) else { throw ContributionError.unavailable }
        return url
    }

    private func send(_ request: URLRequest) async throws -> (Int, Data) {
        var request = request
        request.setValue(AppIdentity.appVersion, forHTTPHeaderField: "X-App-Version")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ContributionError.unavailable }
            return (http.statusCode, data)
        } catch let error as ContributionError {
            throw error
        } catch {
            throw ContributionError.unavailable
        }
    }

    private static func errorCode(_ data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    }

    /// Maps a non-2xx answer. A 404 is "unknown contributor" only when
    /// the server says so in its error body; any other 404 means the
    /// endpoint does not exist (older server).
    private static func failure(_ status: Int, _ data: Data) -> ContributionError {
        let code = errorCode(data)
        switch (status, code) {
        case (404, "contributor_not_found"): return .unknownContributor
        case (403, "contributor_not_approved"): return .notApproved
        case (413, _): return .tooLarge
        case (409, _): return .illegalState
        case (400, let c?): return .rejected(c)
        default: return .unavailable
        }
    }

    private func bodiless(_ method: String, path: String, contributorId: UUID) async throws -> (Int, Data) {
        let query = "contributorId=\(contributorId.uuidString.lowercased())"
        let payload = ContributionAttest.bodilessPayload(method: method, path: path, rawQuery: query)
        var request = URLRequest(url: try url(path: path, rawQuery: query))
        request.httpMethod = method
        request.timeoutInterval = 15
        for (k, v) in try await headers(payload: payload) { request.setValue(v, forHTTPHeaderField: k) }
        return try await send(request)
    }

    private func postJSON(path: String, body: Data) async throws -> (Int, Data) {
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in try await headers(payload: body) { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = body
        return try await send(request)
    }

    private func postMultipart(path: String, parts: [MultipartPart]) async throws -> (Int, Data) {
        let payload = ContributionAttest.multipartPayload(path: path, parts: parts)
        let (body, contentType) = MultipartBody.encode(parts)
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (k, v) in try await headers(payload: payload) { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = body
        return try await send(request)
    }

    // MARK: Endpoints

    func apply(contributorId: UUID, note: String) async throws -> String {
        struct Body: Encodable { let contributorId: String; let note: String }
        struct Response: Decodable { let status: String }
        let body = try JSONEncoder().encode(Body(contributorId: contributorId.uuidString.lowercased(), note: note))
        let (status, data) = try await postJSON(path: Self.base + "/applications", body: body)
        guard (200..<300).contains(status) else { throw Self.failure(status, data) }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { throw ContributionError.unavailable }
        return r.status
    }

    func standing(contributorId: UUID) async throws -> ContributorStanding {
        let (status, data) = try await bodiless("GET", path: Self.base + "/status", contributorId: contributorId)
        guard status == 200 else { throw Self.failure(status, data) }
        guard let s = try? JSONDecoder().decode(ContributorStanding.self, from: data) else {
            throw ContributionError.unavailable
        }
        return s
    }

    func spendAdFree(contributorId: UUID) async throws -> SpendResult {
        let body = Data("{\"contributorId\":\"\(contributorId.uuidString.lowercased())\"}".utf8)
        let (status, data) = try await postJSON(path: Self.base + "/adfree/spend", body: body)
        guard status == 200 else { throw Self.failure(status, data) }
        guard let r = try? JSONDecoder().decode(SpendResult.self, from: data) else { throw ContributionError.unavailable }
        return r
    }

    func samples(contributorId: UUID) async throws -> [SampleSummary] {
        let (status, data) = try await bodiless("GET", path: Self.base + "/samples", contributorId: contributorId)
        guard status == 200 else { throw Self.failure(status, data) }
        guard let list = try? JSONDecoder().decode([SampleSummary].self, from: data) else {
            throw ContributionError.unavailable
        }
        return list
    }

    func sample(id: Int64, contributorId: UUID) async throws -> SampleSummary {
        let (status, data) = try await bodiless("GET", path: Self.base + "/samples/\(id)", contributorId: contributorId)
        guard status == 200 else { throw Self.failure(status, data) }
        guard let s = try? JSONDecoder().decode(SampleSummary.self, from: data) else { throw ContributionError.unavailable }
        return s
    }

    func withdraw(id: Int64, contributorId: UUID) async throws {
        let (status, data) = try await bodiless("DELETE", path: Self.base + "/samples/\(id)", contributorId: contributorId)
        guard status == 204 || status == 200 else { throw Self.failure(status, data) }
    }

    /// FIX12 compatibility: when `compatParts` is given (the same request
    /// minus the vision fields) and the server answers 400 (an older
    /// server), it is sent once instead. The attest payload is rebuilt by
    /// postMultipart for each request.
    func submit(parts: [MultipartPart], compatParts: [MultipartPart]? = nil) async throws -> SampleSummary {
        var (status, data) = try await postMultipart(path: Self.base + "/samples", parts: parts)
        if status == 400, let compatParts {
            (status, data) = try await postMultipart(path: Self.base + "/samples", parts: compatParts)
        }
        guard status == 201 || status == 200 else { throw Self.failure(status, data) }
        guard let s = try? JSONDecoder().decode(SampleSummary.self, from: data) else { throw ContributionError.unavailable }
        return s
    }

    /// FIX12 compatibility retry as for `submit`.
    func append(sampleId: Int64, parts: [MultipartPart],
                compatParts: [MultipartPart]? = nil) async throws -> SampleSummary {
        let path = Self.base + "/samples/\(sampleId)/parts"
        var (status, data) = try await postMultipart(path: path, parts: parts)
        if status == 400, let compatParts {
            (status, data) = try await postMultipart(path: path, parts: compatParts)
        }
        guard status == 200 else { throw Self.failure(status, data) }
        guard let s = try? JSONDecoder().decode(SampleSummary.self, from: data) else { throw ContributionError.unavailable }
        return s
    }
}

// MARK: - Program state

@MainActor
final class ContributorProgram: ObservableObject {
    static let shared = ContributorProgram()

    enum Phase: Equatable {
        /// No contributor id on this device yet (never applied).
        case notEnrolled
        case loading
        case enrolled(ContributorStatus)
        /// Endpoints missing / offline: "not available yet".
        case unavailable
    }

    @Published private(set) var phase: Phase
    @Published private(set) var adFreeBalance = 0
    @Published private(set) var adExemptPermanent = false
    @Published private(set) var samples: [SampleSummary] = []
    @Published private(set) var samplesUnavailable = false

    private let defaults = UserDefaults.standard
    private enum Key {
        static let cache = "contrib.standing"
    }

    private var environment: ServerEnvironment { AppIdentity.effectiveEnvironment }
    private var client: ContributionClient { ContributionClient(environment: environment) }
    private var cacheKey: String { Key.cache + "." + environment.rawValue }

    var contributorId: UUID? { ContributorIdentity.existing }
    var isApproved: Bool { phase == .enrolled(.approved) }
    /// Program member for the record page's member-only steps: applied
    /// and PENDING or APPROVED (a pending member may prepare a complete
    /// sample while waiting). Never applied, DECLINED, REVOKED, or an
    /// unknown standing (loading / unavailable) = not a member. Same
    /// per-environment cached standing as the program home.
    var isMember: Bool { phase == .enrolled(.pending) || phase == .enrolled(.approved) }
    /// FIX7: applied and awaiting owner approval (sees the locked submit button).
    var isPending: Bool { phase == .enrolled(.pending) }
    /// The "Use 1 ad-free unit" offer applies.
    var canSpendAdFree: Bool { isApproved && adFreeBalance > 0 && !adExemptPermanent }

    private init() {
        phase = ContributorIdentity.existing == nil ? .notEnrolled : .loading
        // Last known standing, so a launch without network keeps the
        // contributor's permanent exemption and balance display.
        if ContributorIdentity.existing != nil,
           let data = defaults.data(forKey: Key.cache + "." + AppIdentity.effectiveEnvironment.rawValue),
           let cached = try? JSONDecoder().decode(ContributorStanding.self, from: data) {
            apply(cached)
        }
    }

    private func apply(_ standing: ContributorStanding) {
        if let s = standing.parsedStatus {
            phase = .enrolled(s)
        } else {
            phase = .unavailable
        }
        adFreeBalance = max(0, standing.adFreeBalance)
        adExemptPermanent = standing.adExemptPermanent ?? false
        CreditWallet.shared.setContributorExempt(adExemptPermanent && phase == .enrolled(.approved))
    }

    /// Refreshes the standing. Silent on failure (keeps the cached view
    /// when there is one).
    func refresh() async {
        guard let id = contributorId else {
            phase = .notEnrolled
            return
        }
        do {
            let standing = try await client.standing(contributorId: id)
            apply(standing)
            if let data = try? JSONEncoder().encode(standing) { defaults.set(data, forKey: cacheKey) }
        } catch ContributionError.unknownContributor {
            // Id on the Keychain but this backend has no application
            // (e.g. another environment): the user may apply again.
            phase = .notEnrolled
            adFreeBalance = 0
            adExemptPermanent = false
            CreditWallet.shared.setContributorExempt(false)
        } catch {
            if case .enrolled = phase { return } // keep the cached standing
            phase = .unavailable
        }
    }

    /// Generates the Keychain id (first time) and files the application.
    func apply(note: String) async throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContributionError.rejected("note") }
        guard let id = ContributorIdentity.obtain() else { throw ContributionError.unavailable }
        let status = try await client.apply(contributorId: id, note: String(trimmed.prefix(1000)))
        phase = ContributorStatus(rawValue: status).map { .enrolled($0) } ?? .unavailable
        await refresh()
    }

    enum SpendOutcome { case spent, exempt, failed }

    /// Spends one ad-free unit to unlock the session (approved contributors).
    func spendAdFreeUnit() async -> SpendOutcome {
        guard let id = contributorId else { return .failed }
        do {
            let r = try await client.spendAdFree(contributorId: id)
            adFreeBalance = max(0, r.balance)
            if r.exempt {
                adExemptPermanent = true
                CreditWallet.shared.setContributorExempt(true)
                return .exempt
            }
            return r.spent ? .spent : .failed
        } catch {
            await refresh()
            return .failed
        }
    }

    // MARK: Samples

    func loadSamples() async {
        guard let id = contributorId else { return }
        do {
            samples = try await client.samples(contributorId: id)
            samplesUnavailable = false
            for s in samples { MelonRecordStore.shared.applyServerState(s) }
        } catch {
            samplesUnavailable = true
        }
    }

    func withdraw(_ sampleId: Int64) async throws {
        guard let id = contributorId else { throw ContributionError.unavailable }
        try await client.withdraw(id: sampleId, contributorId: id)
        samples.removeAll { $0.id == sampleId }
        if let record = MelonRecordStore.shared.record(sampleId: sampleId) {
            MelonRecordStore.shared.update(record.id) { $0.submission?.serverStatus = "WITHDRAWN" }
        }
    }

    /// Refreshes one record's mirrored sample state from the server.
    func refreshSample(of record: MelonRecord) async {
        guard let id = contributorId, let sampleId = record.submittedSampleId,
              record.submission?.serverStatus != "WITHDRAWN" else { return }
        if let s = try? await client.sample(id: sampleId, contributorId: id) {
            MelonRecordStore.shared.applyServerState(s)
        }
    }

    /// "Contribute this melon": the record as one sample package.
    func submit(_ record: MelonRecord) async throws {
        guard let id = contributorId else { throw ContributionError.unavailable }
        guard let variety = record.variety else { throw ContributionError.rejected("variety") }
        let store = MelonRecordStore.shared
        var meta: [String: Any] = [
            "contributorId": id.uuidString.lowercased(),
            "variety": variety.rawValue,
            "melonDate": Self.dayString(record.createdAt),
        ]
        if let w = record.weightGrams, w > 0 {
            meta["weightGrams"] = w
            if let p = record.weightProvenance { meta["weightProvenance"] = p.rawValue }
        }
        if let fb = record.feedback { meta["feedback"] = Self.feedbackJSON(fb) }
        var parts: [MultipartPart] = []
        var photoIds: [UUID] = []
        for photo in record.photos.prefix(12) {
            if let part = try await Self.photoPart(photo, name: "appearance", record: record.id, store: store) {
                parts.append(part)
                photoIds.append(photo.id)
            }
        }
        let thump = record.contributableThump
        if let thump, let url = thump.recordingURL, let data = try? Data(contentsOf: url) {
            parts.append(MultipartPart(name: "recording", filename: "recording.wav", contentType: "audio/wav", data: data))
        }
        var cutOpenId: UUID?
        if let cut = record.cutOpenPhoto,
           let part = try await Self.photoPart(cut, name: "cutOpen", record: record.id, store: store) {
            parts.append(part)
            cutOpenId = cut.id
        }
        // FIX12: Vision annotation over what this sample carries.
        let vision = await Self.visionMeta(appearance: record.photos.filter { photoIds.contains($0.id) },
                                           cutOpen: cutOpenId == nil ? nil : record.cutOpenPhoto,
                                           record: record.id, store: store)
        let (primary, compat) = try Self.withMeta(meta, vision: vision, files: parts)
        parts = primary
        let summary = try await client.submit(parts: primary, compatParts: compat)
        let sent = parts.contains { $0.name == "recording" } ? thump?.id : nil
        store.update(record.id) {
            $0.submission = RecordSubmission(
                sampleId: summary.id, submittedAt: Date(), serverStatus: summary.status,
                returnReason: summary.returnReason, uploadedPhotoIds: photoIds, uploadedThumpId: sent,
                uploadedCutOpenId: cutOpenId, uploadedFeedback: record.feedback)
        }
        await loadSamples()
    }

    /// What "Send updates" would append for a submitted record.
    static func pendingAppend(_ record: MelonRecord) -> (photos: [RecordPhoto], cutOpen: RecordPhoto?,
                                                         thump: RecordThump?, feedback: MelonFeedback?) {
        guard let sub = record.submission else { return ([], nil, nil, nil) }
        let room = max(0, 12 - sub.uploadedPhotoIds.count)
        let photos = Array(record.photos.filter { !sub.uploadedPhotoIds.contains($0.id) }.prefix(room))
        let cut = record.cutOpenPhoto.flatMap { $0.id == sub.uploadedCutOpenId ? nil : $0 }
        let thump = record.contributableThump.flatMap { $0.id == sub.uploadedThumpId ? nil : $0 }
        let fb = record.feedback.flatMap { $0 == sub.uploadedFeedback ? nil : $0 }
        return (photos, cut, thump, fb)
    }

    static func hasPendingAppend(_ record: MelonRecord) -> Bool {
        let p = pendingAppend(record)
        return !p.photos.isEmpty || p.cutOpen != nil || p.thump != nil || p.feedback != nil
    }

    /// Later appends (cut-open photo + feedback after eating, more photos,
    /// a newer recording) through POST /samples/{id}/parts.
    func appendUpdates(_ record: MelonRecord) async throws {
        guard let id = contributorId, let sub = record.submission else { throw ContributionError.unavailable }
        let store = MelonRecordStore.shared
        let pending = Self.pendingAppend(record)
        var meta: [String: Any] = ["contributorId": id.uuidString.lowercased()]
        if let fb = pending.feedback { meta["feedback"] = Self.feedbackJSON(fb) }
        var parts: [MultipartPart] = []
        var photoIds: [UUID] = []
        for photo in pending.photos {
            if let part = try await Self.photoPart(photo, name: "appearance", record: record.id, store: store) {
                parts.append(part)
                photoIds.append(photo.id)
            }
        }
        var sentThump: UUID?
        if let thump = pending.thump, let url = thump.recordingURL, let data = try? Data(contentsOf: url) {
            parts.append(MultipartPart(name: "recording", filename: "recording.wav", contentType: "audio/wav", data: data))
            sentThump = thump.id
        }
        var sentCut: UUID?
        if let cut = pending.cutOpen,
           let part = try await Self.photoPart(cut, name: "cutOpen", record: record.id, store: store) {
            parts.append(part)
            sentCut = cut.id
        }
        // FIX12: Vision annotation over the sample as it stands after this
        // append: the photos already uploaded plus the new ones, and the
        // cut-open photo the sample will carry.
        let sampleIds = Set(sub.uploadedPhotoIds + photoIds)
        let cutId = sentCut ?? sub.uploadedCutOpenId
        let vision = await Self.visionMeta(appearance: record.photos.filter { sampleIds.contains($0.id) },
                                           cutOpen: record.cutOpenPhoto.flatMap { $0.id == cutId ? $0 : nil },
                                           record: record.id, store: store)
        let (primary, compat) = try Self.withMeta(meta, vision: vision, files: parts)
        let summary = try await client.append(sampleId: sub.sampleId, parts: primary, compatParts: compat)
        store.update(record.id) { r in
            r.submission?.serverStatus = summary.status
            r.submission?.returnReason = summary.returnReason
            r.submission?.uploadedPhotoIds += photoIds
            if let sentThump { r.submission?.uploadedThumpId = sentThump }
            if let sentCut { r.submission?.uploadedCutOpenId = sentCut }
            if pending.feedback != nil { r.submission?.uploadedFeedback = pending.feedback }
        }
        await loadSamples()
    }

    // MARK: Helpers

    /// The meta part (plus FIX12 vision fields when any score exists)
    /// followed by the file parts, and — only when vision fields were
    /// added — the same request without them for the 400 retry.
    private static func withMeta(_ meta: [String: Any], vision: [String: Double],
                                 files: [MultipartPart]) throws -> ([MultipartPart], [MultipartPart]?) {
        func metaPart(_ m: [String: Any]) throws -> MultipartPart {
            MultipartPart(name: "meta", filename: nil, contentType: "application/json",
                          data: try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]))
        }
        let plain = [try metaPart(meta)] + files
        guard !vision.isEmpty else { return (plain, nil) }
        let annotated = meta.merging(vision.mapValues { $0 as Any }) { _, new in new }
        return ([try metaPart(annotated)] + files, plain)
    }

    /// FIX12: `visionWatermelon` = best score among the appearance photos,
    /// `visionCutopenWatermelon` = the cut-open photo's score. Scores from
    /// capture time are reused; photos without one are classified now
    /// (and the score kept on the photo). A key is present only when a
    /// score exists.
    private static func visionMeta(appearance: [RecordPhoto], cutOpen: RecordPhoto?, record: UUID,
                                   store: MelonRecordStore) async -> [String: Double] {
        func score(_ photo: RecordPhoto) async -> Double? {
            if let s = photo.visionWatermelon { return s }
            let s = await WatermelonVision.score(url: store.url(of: photo, in: record))
            store.setVisionWatermelon(s, photoId: photo.id, in: record)
            return s
        }
        func wire(_ s: Double) -> Double { (min(1, max(0, s)) * 10_000).rounded() / 10_000 }
        var out: [String: Double] = [:]
        var best: Double?
        for photo in appearance {
            if let s = await score(photo) { best = max(best ?? s, s) }
        }
        if let best { out["visionWatermelon"] = wire(best) }
        if let cutOpen, let s = await score(cutOpen) { out["visionCutopenWatermelon"] = wire(s) }
        return out
    }

    private static func photoPart(_ photo: RecordPhoto, name: String, record: UUID,
                                  store: MelonRecordStore) async throws -> MultipartPart? {
        let url = store.url(of: photo, in: record)
        let type = photo.contentType
        let encoded = await Task.detached(priority: .userInitiated) {
            RecordImage.uploadData(at: url, contentType: type)
        }.value
        guard let (data, contentType) = encoded else { return nil }
        return MultipartPart(name: name, filename: "\(name).\(MelonRecordStore.fileExtension(for: contentType))",
                             contentType: contentType, data: data)
    }

    private static func feedbackJSON(_ fb: MelonFeedback) -> [String: Any] {
        ["score": max(0, min(100, fb.score)), "tasteTags": fb.tasteTags.map(\.rawValue), "bandTruth": fb.bandTruth.rawValue]
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

extension MelonRecordStore {
    /// Mirrors the server's view of a sample onto its record.
    func applyServerState(_ s: SampleSummary) {
        guard let record = record(sampleId: s.id),
              record.submission?.serverStatus != s.status || record.submission?.returnReason != s.returnReason
        else { return }
        update(record.id) {
            $0.submission?.serverStatus = s.status
            $0.submission?.returnReason = s.returnReason
        }
    }
}
