import Foundation
import SwiftUI
import UIKit

// MARK: - Melon record (design doc 2.0 §2 item 8)
//
// One reopenable on-device record per melon: appearance photos, the
// thumps made for it (linked to the RecordingArchive files, never a
// second copy of the audio), the three-band verdicts, bookkeeping
// (variety by selection, weight + provenance, date), the cut-open
// photo and the user's own feedback. For ordinary users the record list
// is simply their thump history and never leaves the phone; a
// contributor may mirror one record to the server as a sample package.
//
// Storage: Documents/MelonRecords/index.json (the whole list, newest
// first, written atomically on every change) plus one folder per record,
// Documents/MelonRecords/<record id>/, holding its photos at full quality.
// No model score lives here (design §6 gates not met yet): the verdict
// is the existing three-band result.

enum MelonVariety: String, Codable, CaseIterable, Identifiable, Sendable {
    // Raw values are the server's preset names (design §7 item 7).
    case seedless = "SEEDLESS"
    case seeded = "SEEDED"
    case mini = "MINI"
    case yellowFlesh = "YELLOW_FLESH"
    case kirin = "KIRIN"
    case blackBeauty = "BLACK_BEAUTY"
    case other = "OTHER"

    var id: String { rawValue }

    func displayName(_ l: L10n) -> String {
        switch self {
        case .seedless: return l.t("variety.seedless")
        case .seeded: return l.t("variety.seeded")
        case .mini: return l.t("variety.mini")
        case .yellowFlesh: return l.t("variety.yellowFlesh")
        case .kirin: return l.t("variety.kirin")
        case .blackBeauty: return l.t("variety.blackBeauty")
        case .other: return l.t("variety.other")
        }
    }
}

enum WeightProvenance: String, Codable, CaseIterable, Sendable {
    case scaleMeasured = "SCALE_MEASURED"
    case manualEstimate = "MANUAL_ESTIMATE"
    /// In the data model for a later estimator; never produced in 2.0.
    case photoEstimated = "PHOTO_ESTIMATED"

    func displayName(_ l: L10n) -> String {
        switch self {
        case .scaleMeasured: return l.t("weight.scale")
        case .manualEstimate: return l.t("weight.estimate")
        case .photoEstimated: return l.t("weight.photo")
        }
    }
}

enum TasteTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case crisp = "CRISP", mealy = "MEALY", sandy = "SANDY", juicy = "JUICY", sweet = "SWEET", bland = "BLAND"
    var id: String { rawValue }

    func displayName(_ l: L10n) -> String { l.t("taste.\(rawValue.lowercased())") }
}

/// The three bands as ground truth (server BandTruth).
enum BandTruth: String, Codable, CaseIterable, Identifiable, Sendable {
    case unripe = "UNRIPE", ripe = "RIPE", overripe = "OVERRIPE"
    var id: String { rawValue }

    func displayName(_ l: L10n) -> String {
        switch self {
        case .unripe: return l.t("band.unripe")
        case .ripe: return l.t("band.ripe")
        case .overripe: return l.t("band.overripe")
        }
    }
}

enum PhotoKind: String, Codable, Sendable {
    /// Rind texture close-up (primary).
    case rindCloseUp = "RIND"
    /// Whole melon, ideally with a bank card beside it (secondary).
    case wholeMelon = "WHOLE"
    case cutOpen = "CUT_OPEN"
}

struct RecordPhoto: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: PhotoKind
    /// File name inside the record's folder.
    var fileName: String
    var contentType: String
    var addedAt: Date
    /// FIX12: Vision `watermelon` confidence computed when the photo was
    /// taken / picked (nil = not classified, or Vision had no opinion).
    /// Drives the record page's warning caption and is reused for the
    /// sample annotation. Older photos decode with nil.
    var visionWatermelon: Double?
}

struct RecordThump: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var analyzedAt: Date
    /// RecordingArchive stem (Documents/Recordings/<stem>.wav + .json);
    /// nil until the archive copy is written, or if it failed.
    var archiveStem: String?
    var verdict: String
    var confidence: Double
    var dominantFrequencyHz: Double
    var decayTimeMs: Double
    var modelId: String
    var modelVersion: String
}

struct MelonFeedback: Codable, Equatable, Sendable {
    /// The user's OWN score, 0–100 (not a model score).
    var score: Int
    var tasteTags: [TasteTag]
    var bandTruth: BandTruth
}

/// Contribution mirror of one record (contributors only).
struct RecordSubmission: Codable, Equatable, Sendable {
    var sampleId: Int64
    var submittedAt: Date
    /// Last server status seen: SUBMITTED / APPROVED / RETURNED / VOIDED,
    /// or WITHDRAWN after a successful self-service delete.
    var serverStatus: String
    var returnReason: String?
    /// What has reached the server, so "Send updates" appends only the rest.
    var uploadedPhotoIds: [UUID]
    var uploadedThumpId: UUID?
    var uploadedCutOpenId: UUID?
    var uploadedFeedback: MelonFeedback?
}

struct MelonRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var variety: MelonVariety?
    var weightGrams: Int?
    var weightProvenance: WeightProvenance?
    /// Appearance photos (rind close-ups and whole-melon shots).
    var photos: [RecordPhoto]
    var thumps: [RecordThump]
    var cutOpenPhoto: RecordPhoto?
    var feedback: MelonFeedback?
    var submission: RecordSubmission?
    /// True for records created implicitly by a home-screen thump.
    var fromHomeThump: Bool

    /// The nullable server sample id (spec field name).
    var submittedSampleId: Int64? { submission?.sampleId }

    /// The record's verdict: the newest real (non-UNKNOWN) thump, else
    /// the newest thump, else nil.
    var verdict: String? {
        thumps.last(where: { $0.verdict != Ripeness.unknown.rawValue })?.verdict ?? thumps.last?.verdict
    }

    /// FIX2: the photos-first rule (owner-amended 2026-11-08) — a thump
    /// may be recorded for this melon only once it has at least ONE
    /// appearance photo: a rind close-up OR a whole-melon photo, either
    /// kind alone suffices (camera or library, same slots).
    var hasRequiredPhotos: Bool {
        photos.contains { $0.kind == .rindCloseUp || $0.kind == .wholeMelon }
    }

    /// FIX2: a record that holds nothing at all (e.g. created by the
    /// photo gate and then left without a photo).
    var isBlank: Bool { thumps.isEmpty && !hasUserContent }

    var thumbnailPhoto: RecordPhoto? {
        photos.first(where: { $0.kind == .rindCloseUp }) ?? photos.first
    }

    /// Anything the user added by hand: such records keep their linked
    /// recordings out of the archive's newest-20 retention sweep.
    var hasUserContent: Bool {
        !photos.isEmpty || cutOpenPhoto != nil || feedback != nil || variety != nil
            || weightGrams != nil || submission != nil || !fromHomeThump
    }

    /// The thump whose recording a contribution sends: newest real thump
    /// with a recording file still on the device.
    var contributableThump: RecordThump? {
        thumps.reversed().first { $0.verdict != Ripeness.unknown.rawValue && $0.recordingURL != nil }
            ?? thumps.reversed().first { $0.recordingURL != nil }
    }
}

extension RecordThump {
    /// The archived WAV, if still on the device (retention may prune it).
    var recordingURL: URL? {
        guard let archiveStem else { return nil }
        let url = RecordingArchive.folder.appendingPathComponent(archiveStem + ".wav")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

@MainActor
final class MelonRecordStore: ObservableObject {
    static let shared = MelonRecordStore()

    /// Newest first.
    @Published private(set) var records: [MelonRecord] = []

    /// A home-screen thump continues the newest home-created record only
    /// while that record holds nothing but UNKNOWN takes (the user is
    /// still trying to get a reading of the same melon) and is recent.
    static let homeContinueWindow: TimeInterval = 15 * 60

    nonisolated static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MelonRecords", isDirectory: true)
    }

    private var indexURL: URL { Self.folder.appendingPathComponent("index.json") }

    private init() {
        load()
    }

    func record(id: UUID) -> MelonRecord? { records.first { $0.id == id } }

    func record(sampleId: Int64) -> MelonRecord? { records.first { $0.submission?.sampleId == sampleId } }

    // MARK: - Creation

    @discardableResult
    func createRecord(fromHomeThump: Bool = false) -> MelonRecord {
        let now = Date()
        let record = MelonRecord(
            id: UUID(), createdAt: now, updatedAt: now, variety: nil, weightGrams: nil,
            weightProvenance: nil, photos: [], thumps: [], cutOpenPhoto: nil, feedback: nil,
            submission: nil, fromHomeThump: fromHomeThump)
        records.insert(record, at: 0)
        persist()
        return record
    }

    /// Attaches one completed analysis. With a target record (the user
    /// chose "Thump this melon" in a record) it goes there; otherwise the
    /// home flow creates a record in the background (or continues an
    /// UNKNOWN-only one). Returns (record id, thump id).
    @discardableResult
    func attachThump(_ result: TapResult, modelId: String, modelVersion: String,
                     target: UUID?, at date: Date = Date()) -> (UUID, UUID) {
        let thump = RecordThump(
            id: UUID(), analyzedAt: date, archiveStem: nil, verdict: result.verdict,
            confidence: result.confidence, dominantFrequencyHz: result.dominantFrequencyHz,
            decayTimeMs: result.decayTimeMs, modelId: modelId, modelVersion: modelVersion)
        let recordId = boundRecordId(target: target, at: date) ?? createRecord(fromHomeThump: true).id
        update(recordId) { $0.thumps.append(thump) }
        return (recordId, thump.id)
    }

    /// The existing record a thump binds to: the target record if it still
    /// exists, else the open UNKNOWN-only home record (recent, not
    /// contributed); nil = a new record. FIX2: the photo gate checks the
    /// same binding before recording starts.
    func boundRecordId(target: UUID?, at date: Date = Date()) -> UUID? {
        if let target, record(id: target) != nil {
            return target
        } else if let open = records.first(where: { $0.fromHomeThump }),
                  !open.thumps.isEmpty,
                  open.thumps.allSatisfy({ $0.verdict == Ripeness.unknown.rawValue }),
                  date.timeIntervalSince(open.updatedAt) < Self.homeContinueWindow,
                  open.submission == nil {
            return open.id
        }
        return nil
    }

    /// Links the archive copy once RecordingArchive has written it.
    func linkRecording(stem: String, thumpId: UUID) {
        guard let index = records.firstIndex(where: { $0.thumps.contains { $0.id == thumpId } }) else { return }
        update(records[index].id) { record in
            if let t = record.thumps.firstIndex(where: { $0.id == thumpId }) {
                record.thumps[t].archiveStem = stem
            }
        }
    }

    // MARK: - Editing

    func update(_ id: UUID, _ change: (inout MelonRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        var record = records[index]
        change(&record)
        record.updatedAt = Date()
        records[index] = record
        persist()
    }

    /// Stores a photo at full quality in the record's folder.
    @discardableResult
    func addPhoto(_ data: Data, contentType: String, kind: PhotoKind, to id: UUID,
                  visionWatermelon: Double? = nil) throws -> RecordPhoto {
        let photo = RecordPhoto(id: UUID(), kind: kind,
                                fileName: "\(kind.rawValue.lowercased())-\(UUID().uuidString.prefix(8)).\(Self.fileExtension(for: contentType))",
                                contentType: contentType, addedAt: Date(), visionWatermelon: visionWatermelon)
        let dir = Self.folder.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(photo.fileName), options: .atomic)
        var replaced: RecordPhoto?
        update(id) { record in
            if kind == .cutOpen {
                replaced = record.cutOpenPhoto
                record.cutOpenPhoto = photo
            } else {
                record.photos.append(photo)
            }
        }
        if let replaced { try? FileManager.default.removeItem(at: url(of: replaced, in: id)) }
        return photo
    }

    /// FIX12: records a photo's Vision score once classified (no-op if the
    /// photo has gone in the meantime).
    func setVisionWatermelon(_ score: Double?, photoId: UUID, in id: UUID) {
        guard let score else { return }
        update(id) { record in
            if let i = record.photos.firstIndex(where: { $0.id == photoId }) {
                record.photos[i].visionWatermelon = score
            } else if record.cutOpenPhoto?.id == photoId {
                record.cutOpenPhoto?.visionWatermelon = score
            }
        }
    }

    func removePhoto(_ photo: RecordPhoto, from id: UUID) {
        update(id) { record in
            record.photos.removeAll { $0.id == photo.id }
            if record.cutOpenPhoto?.id == photo.id { record.cutOpenPhoto = nil }
        }
        try? FileManager.default.removeItem(at: url(of: photo, in: id))
    }

    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
        persist()
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    nonisolated func url(of photo: RecordPhoto, in recordId: UUID) -> URL {
        Self.folder.appendingPathComponent(recordId.uuidString, isDirectory: true)
            .appendingPathComponent(photo.fileName)
    }

    nonisolated static func fileExtension(for contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/png": return "png"
        case "image/webp": return "webp"
        default: return "jpg"
        }
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = (try? decoder.decode([MelonRecord].self, from: data)) ?? []
        }
        syncPins()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: indexURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[MelonRecordStore] persist failed: \(error)")
            #endif
        }
        syncPins()
    }

    /// Recordings of records the user has worked on are exempt from the
    /// archive's newest-20 sweep; plain background thump history follows
    /// the normal retention.
    private func syncPins() {
        let stems = records.filter(\.hasUserContent).flatMap { $0.thumps.compactMap(\.archiveStem) }
        RecordingArchive.setPinnedStems(Set(stems))
    }
}

// MARK: - Photo helpers

enum RecordImage {
    /// A downscaled thumbnail for lists (decoded off the main thread by
    /// the caller's task).
    nonisolated static func thumbnail(at url: URL, maxPixel: CGFloat = 240) -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.preparingThumbnail(of: CGSize(width: maxPixel, height: maxPixel * image.size.height / max(image.size.width, 1)))
            ?? image
    }

    /// Upload copy within the server's 10 MB photo limit: the stored
    /// bytes when small enough, else a JPEG re-encode (scaled if needed).
    nonisolated static func uploadData(at url: URL, contentType: String) -> (Data, String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let limit = 10 * 1024 * 1024
        if data.count <= limit { return (data, contentType) }
        guard var image = UIImage(data: data) else { return nil }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= limit {
                return (jpeg, "image/jpeg")
            }
        }
        while image.size.width > 800 {
            let size = CGSize(width: image.size.width * 0.7, height: image.size.height * 0.7)
            image = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpeg = image.jpegData(compressionQuality: 0.8), jpeg.count <= limit {
                return (jpeg, "image/jpeg")
            }
        }
        return nil
    }
}
