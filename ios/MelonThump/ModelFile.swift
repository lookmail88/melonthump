import Foundation

// MARK: - .ml model files (design doc 1.2.0 §1, docs/ml-format.md v1)
//
// The analysis model is data: a `.ml` file is a UTF-8 JSON document
// carrying every tunable of the analyzer. The built-in model, Baby 1.0,
// ships twice — as the bundled `baby-1.0.ml` and as the compiled-in
// constants below (HeuristicBandsParameters.babyV22) — so a missing or
// invalid bundled file can never take analysis down. External files in
// Documents/Models are scanned once at launch, read-only; an invalid one
// is skipped whole, never partially applied, and never crashes the app.

/// The loader seam (design doc §1): every model kind implements this,
/// so a real machine-learning model can later replace the heuristic
/// behind the same interface. Format v1 knows one kind,
/// "heuristic-bands"; other kinds are skipped by this loader.
protocol ThumpModel: Sendable {
    var descriptor: ModelDescriptor { get }
    func analyze(audioURL: URL) throws -> TapResult
}

/// How a model is offered in the picker. Paid models (StoreKit) are a
/// later release: the case exists so the picker can render one, but no
/// paid model and no purchase flow ship in 1.2.0.
enum ModelOffer: Hashable, Sendable {
    case free
    case paid(productId: String)
}

enum ModelSource: Hashable, Sendable {
    /// Baby 1.0 from the bundled file.
    case bundled
    /// Baby 1.0 from the compiled-in constants (bundled file missing/invalid).
    case builtInConstants
    /// A valid file from Documents/Models (file name).
    case external(String)
}

struct ModelDescriptor: Identifiable, Hashable, Sendable {
    let modelId: String
    let modelVersion: String
    let displayName: String
    let kind: String
    let source: ModelSource
    let offer: ModelOffer

    var id: String { modelId }
    var isDefault: Bool { modelId == ModelFormat.builtInModelId }
}

enum ModelFormat {
    static let fileExtension = "ml"
    static let supportedFormatVersion = 1.0
    static let maxFileBytes = 64 * 1024
    static let builtInModelId = "baby-1.0"
    static let heuristicBandsKind = "heuristic-bands"
    /// Corrected per the 2026-11-05 adjudication: the dot is allowed
    /// (the reserved id `baby-1.0` contains one).
    static let modelIdCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
    static let maxIdLength = 64
    static let maxLabelLength = 64
}

// MARK: - heuristic-bands parameters (heuristic v2.2, complete set)

/// Every numeric tunable `LocalAnalyzer` uses. Field names are the JSON
/// keys of the file's `parameters` object; all are required.
///
/// Verdict bands (adjudicated 2026-11-05 — follow the v2.2 code, bit
/// for bit): f < overripeBelowHz → OVERRIPE; overripeBelowHz ≤ f <
/// ripeUpToHz → RIPE; f ≥ ripeUpToHz → UNRIPE (exactly 280 Hz is UNRIPE).
struct HeuristicBandsParameters: Codable, Equatable, Sendable {
    // Verdict bands.
    var overripeBelowHz: Double
    var ripeUpToHz: Double
    // Verdict confidence: base + span × min(1, distance / scale), capped.
    var confidenceBase: Double
    var confidenceSpan: Double
    var confidenceMax: Double
    var unripeConfidenceScaleHz: Double
    var unknownConfidence: Double
    // Envelope framing and the usable window.
    var envelopeFramesPerSecond: Int
    var trimHeadMs: Double
    var trimTailMs: Double
    var minUsableWindowFrames: Int
    // Time-domain thump gates.
    var absoluteFloor: Double
    var peakWidthMinFrames: Int
    var peakWidthLevelRatio: Double
    var prominenceDbMin: Double
    var attackLevelRatio: Double
    var attackMaxMs: Double
    var decayMaxMs: Double
    var sustainedEndLevelRatio: Double
    // Spectrum.
    var segmentMs: Double
    var segmentPrerollMs: Double
    var bandMinHz: Double
    var bandMaxHz: Double
    var crestNeighbourMinHz: Double
    var crestNeighbourMaxHz: Double
    var crestDbMin: Double
    // Spectral SNR against a noise-only segment.
    var snrDbMin: Double
    var noiseSegmentAfterMs: Double
    var noiseSegmentBeforeGapMs: Double
    // Ring pitch consistency.
    var ringMinOffsetMs: Double
    var ringSegmentMs: Double
    var ringTolerance: Double

    /// Compiled-in fallback: heuristic v2.2 exactly (the bundled
    /// baby-1.0.ml carries the same values; a DEBUG launch check
    /// asserts they agree).
    static let babyV22 = HeuristicBandsParameters(
        overripeBelowHz: 160,
        ripeUpToHz: 280,
        confidenceBase: 0.55,
        confidenceSpan: 0.40,
        confidenceMax: 0.95,
        unripeConfidenceScaleHz: 120,
        unknownConfidence: 0.3,
        envelopeFramesPerSecond: 100,
        trimHeadMs: 300,
        trimTailMs: 200,
        minUsableWindowFrames: 10,
        absoluteFloor: 0.002,
        peakWidthMinFrames: 2,
        peakWidthLevelRatio: 0.5,
        prominenceDbMin: 10,
        attackLevelRatio: 0.5,
        attackMaxMs: 80,
        decayMaxMs: 800,
        sustainedEndLevelRatio: 0.6,
        segmentMs: 500,
        segmentPrerollMs: 30,
        bandMinHz: 60,
        bandMaxHz: 600,
        crestNeighbourMinHz: 15,
        crestNeighbourMaxHz: 75,
        crestDbMin: 18,
        snrDbMin: 6,
        noiseSegmentAfterMs: 1200,
        noiseSegmentBeforeGapMs: 300,
        ringMinOffsetMs: 100,
        ringSegmentMs: 250,
        ringTolerance: 0.15)

    /// Range checks beyond the format doc's band rule, so that no file
    /// that validates can make the analyzer misbehave (division by
    /// zero, empty ranges, absurd windows). Returns the failed rule.
    func violation() -> String? {
        let doubles: [(String, Double)] = [
            ("overripeBelowHz", overripeBelowHz), ("ripeUpToHz", ripeUpToHz),
            ("confidenceBase", confidenceBase), ("confidenceSpan", confidenceSpan),
            ("confidenceMax", confidenceMax), ("unripeConfidenceScaleHz", unripeConfidenceScaleHz),
            ("unknownConfidence", unknownConfidence), ("trimHeadMs", trimHeadMs),
            ("trimTailMs", trimTailMs), ("absoluteFloor", absoluteFloor),
            ("peakWidthLevelRatio", peakWidthLevelRatio), ("prominenceDbMin", prominenceDbMin),
            ("attackLevelRatio", attackLevelRatio), ("attackMaxMs", attackMaxMs),
            ("decayMaxMs", decayMaxMs), ("sustainedEndLevelRatio", sustainedEndLevelRatio),
            ("segmentMs", segmentMs), ("segmentPrerollMs", segmentPrerollMs),
            ("bandMinHz", bandMinHz), ("bandMaxHz", bandMaxHz),
            ("crestNeighbourMinHz", crestNeighbourMinHz), ("crestNeighbourMaxHz", crestNeighbourMaxHz),
            ("crestDbMin", crestDbMin), ("snrDbMin", snrDbMin),
            ("noiseSegmentAfterMs", noiseSegmentAfterMs), ("noiseSegmentBeforeGapMs", noiseSegmentBeforeGapMs),
            ("ringMinOffsetMs", ringMinOffsetMs), ("ringSegmentMs", ringSegmentMs),
            ("ringTolerance", ringTolerance),
        ]
        for (name, value) in doubles where !value.isFinite {
            return "\(name) is not finite"
        }
        // docs/ml-format.md item 4.
        guard overripeBelowHz > 0, overripeBelowHz < ripeUpToHz, ripeUpToHz <= 2000 else {
            return "0 < overripeBelowHz < ripeUpToHz <= 2000"
        }
        guard (0...1).contains(confidenceBase), (0...1).contains(confidenceSpan),
              (0...1).contains(confidenceMax), (0...1).contains(unknownConfidence) else {
            return "confidence values must lie in 0...1"
        }
        guard unripeConfidenceScaleHz > 0 else { return "unripeConfidenceScaleHz > 0" }
        guard (10...1000).contains(envelopeFramesPerSecond) else { return "envelopeFramesPerSecond in 10...1000" }
        guard (0...5000).contains(trimHeadMs), (0...5000).contains(trimTailMs) else { return "trim in 0...5000 ms" }
        guard (1...1000).contains(minUsableWindowFrames) else { return "minUsableWindowFrames in 1...1000" }
        guard absoluteFloor >= 0, absoluteFloor < 1 else { return "absoluteFloor in [0, 1)" }
        guard (1...100).contains(peakWidthMinFrames) else { return "peakWidthMinFrames in 1...100" }
        guard peakWidthLevelRatio > 0, peakWidthLevelRatio < 1,
              attackLevelRatio > 0, attackLevelRatio < 1,
              sustainedEndLevelRatio > 0, sustainedEndLevelRatio <= 1 else { return "level ratios in (0, 1)" }
        guard attackMaxMs > 0, decayMaxMs > 0 else { return "attack/decay limits > 0" }
        guard (50...2000).contains(segmentMs), (50...2000).contains(ringSegmentMs) else { return "segments in 50...2000 ms" }
        guard (0...1000).contains(segmentPrerollMs) else { return "segmentPrerollMs in 0...1000" }
        guard bandMinHz > 0, bandMinHz < bandMaxHz, bandMaxHz <= 20000 else { return "0 < bandMinHz < bandMaxHz <= 20000" }
        guard crestNeighbourMinHz >= 0, crestNeighbourMinHz < crestNeighbourMaxHz else { return "crest neighbourhood" }
        guard noiseSegmentAfterMs >= 0, noiseSegmentBeforeGapMs >= 0, ringMinOffsetMs >= 0 else { return "offsets >= 0" }
        guard ringTolerance > 0 else { return "ringTolerance > 0" }
        return nil
    }
}

// MARK: - Loader (validation per docs/ml-format.md item 4)

enum ModelFileError: Error, Equatable, CustomStringConvertible {
    case tooLarge
    case notJSON
    case missingOrMistypedField(String)
    case unsupportedFormatVersion
    case invalidModelId
    case reservedModelId
    case unsupportedKind(String)
    case invalidParameters(String)

    var description: String {
        switch self {
        case .tooLarge: return "file exceeds 64 KB"
        case .notJSON: return "content is not a JSON object"
        case .missingOrMistypedField(let f): return "required field missing or mistyped: \(f)"
        case .unsupportedFormatVersion: return "formatVersion is not 1"
        case .invalidModelId: return "modelId must be [a-z0-9.-]"
        case .reservedModelId: return "modelId baby-1.0 is reserved for the built-in model"
        case .unsupportedKind(let k): return "kind \(k) is not implemented by this loader"
        case .invalidParameters(let rule): return "parameters fail: \(rule)"
        }
    }
}

/// Heuristic-bands model: LocalAnalyzer driven by a parameter set.
struct HeuristicBandsModel: ThumpModel {
    let descriptor: ModelDescriptor
    let parameters: HeuristicBandsParameters

    func analyze(audioURL: URL) throws -> TapResult {
        try LocalAnalyzer.analyze(audioURL: audioURL, parameters: parameters,
                                  modelLabel: "\(descriptor.modelId)/\(descriptor.modelVersion)")
    }
}

enum ModelFileLoader {
    private struct Envelope: Decodable {
        let formatVersion: Double
        let modelId: String
        let modelVersion: String
        let displayName: String
        let kind: String
    }

    private struct HeuristicBandsBody: Decodable {
        let parameters: HeuristicBandsParameters
    }

    /// Decoders per model kind — the seam where future kinds plug in.
    private static let kinds: [String: @Sendable (Data, ModelDescriptor) throws -> any ThumpModel] = [
        ModelFormat.heuristicBandsKind: { data, descriptor in
            let body: HeuristicBandsBody
            do {
                body = try JSONDecoder().decode(HeuristicBandsBody.self, from: data)
            } catch {
                throw ModelFileError.missingOrMistypedField(ModelFileLoader.fieldName(of: error) ?? "parameters")
            }
            if let rule = body.parameters.violation() {
                throw ModelFileError.invalidParameters(rule)
            }
            return HeuristicBandsModel(descriptor: descriptor, parameters: body.parameters)
        },
    ]

    /// Validates and loads one model file's bytes. Pure: never throws
    /// anything but ModelFileError, never traps.
    static func load(data: Data, source: ModelSource, allowReservedId: Bool) throws -> any ThumpModel {
        guard data.count <= ModelFormat.maxFileBytes else { throw ModelFileError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any] else {
            throw ModelFileError.notJSON
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ModelFileError.missingOrMistypedField(fieldName(of: error) ?? "envelope")
        }
        guard envelope.formatVersion == ModelFormat.supportedFormatVersion else {
            throw ModelFileError.unsupportedFormatVersion
        }
        guard !envelope.modelId.isEmpty, envelope.modelId.count <= ModelFormat.maxIdLength,
              envelope.modelId.allSatisfy({ ModelFormat.modelIdCharacters.contains($0) }) else {
            throw ModelFileError.invalidModelId
        }
        if envelope.modelId == ModelFormat.builtInModelId && !allowReservedId {
            throw ModelFileError.reservedModelId
        }
        let name = envelope.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = envelope.modelVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= ModelFormat.maxLabelLength else {
            throw ModelFileError.missingOrMistypedField("displayName")
        }
        guard !version.isEmpty, version.count <= ModelFormat.maxLabelLength else {
            throw ModelFileError.missingOrMistypedField("modelVersion")
        }
        guard let build = kinds[envelope.kind] else {
            throw ModelFileError.unsupportedKind(envelope.kind)
        }
        let descriptor = ModelDescriptor(
            modelId: envelope.modelId, modelVersion: version, displayName: name,
            kind: envelope.kind, source: source, offer: .free)
        return try build(data, descriptor)
    }

    fileprivate static func fieldName(of error: Error) -> String? {
        switch error as? DecodingError {
        case .keyNotFound(let key, _): return key.stringValue
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            return ctx.codingPath.last?.stringValue
        default: return nil
        }
    }

    /// Baby 1.0: the bundled file when it is present and valid, else
    /// the compiled-in constants. Always returns a model.
    static func loadBuiltIn(bundle: Bundle = .main) -> HeuristicBandsModel {
        if let url = bundle.url(forResource: "baby-1.0", withExtension: ModelFormat.fileExtension),
           let data = try? Data(contentsOf: url),
           let model = try? load(data: data, source: .bundled, allowReservedId: true) as? HeuristicBandsModel,
           model.descriptor.modelId == ModelFormat.builtInModelId {
            #if DEBUG
            assert(model.parameters == .babyV22,
                   "bundled baby-1.0.ml drifted from the compiled-in heuristic v2.2 constants")
            #endif
            return model
        }
        return HeuristicBandsModel(
            descriptor: ModelDescriptor(
                modelId: ModelFormat.builtInModelId, modelVersion: "1.0", displayName: "Baby 1.0",
                kind: ModelFormat.heuristicBandsKind, source: .builtInConstants, offer: .free),
            parameters: .babyV22)
    }

    /// Scans a folder (non-recursive) for `*.ml` files in file-name
    /// order. Invalid files are skipped whole; duplicate ids keep the
    /// first file; ids in `taken` (the built-in) always win.
    static func scan(folder: URL, taken: Set<String>) -> (models: [any ThumpModel], skipped: [(String, String)]) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return ([], []) }
        var seen = taken
        var models: [any ThumpModel] = []
        var skipped: [(String, String)] = []
        for name in names.sorted() where name.hasSuffix(".\(ModelFormat.fileExtension)") {
            let url = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            // Size check before reading, so a huge file is never loaded.
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? Int.max
            guard size <= ModelFormat.maxFileBytes else {
                skipped.append((name, ModelFileError.tooLarge.description)); continue
            }
            guard let data = try? Data(contentsOf: url, options: [.uncached]) else {
                skipped.append((name, "unreadable")); continue
            }
            do {
                let model = try load(data: data, source: .external(name), allowReservedId: false)
                guard !seen.contains(model.descriptor.modelId) else {
                    skipped.append((name, "duplicate modelId \(model.descriptor.modelId)")); continue
                }
                seen.insert(model.descriptor.modelId)
                models.append(model)
            } catch {
                skipped.append((name, "\(error)"))
            }
        }
        return (models, skipped)
    }
}

// MARK: - Registry (picker source + active model)

/// All models available this launch: Baby 1.0 first (always present,
/// default, free forever), then valid external files. The selection is
/// persisted and takes effect from the next analysis; a selection whose
/// file disappeared falls back to Baby 1.0.
@MainActor
final class ModelRegistry: ObservableObject {
    static let shared = ModelRegistry()
    static let selectionKey = "model.selectedId"

    @Published private(set) var models: [any ThumpModel] = []
    @Published var selectedId: String {
        didSet { UserDefaults.standard.set(selectedId, forKey: Self.selectionKey) }
    }
    /// Files skipped at launch with the reason (shown nowhere in the UI;
    /// logged in DEBUG for whoever drops a file into Documents/Models).
    private(set) var skipped: [(String, String)] = []

    static var externalFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
    }

    private init() {
        selectedId = UserDefaults.standard.string(forKey: Self.selectionKey) ?? ModelFormat.builtInModelId
        reload()
    }

    /// Launch-time scan (no hot reload in 1.2.0). Creates the folder so
    /// it shows up in the Files app / Finder; files are only ever read.
    func reload() {
        let builtIn = ModelFileLoader.loadBuiltIn()
        let folder = Self.externalFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scan = ModelFileLoader.scan(folder: folder, taken: [builtIn.descriptor.modelId])
        models = [builtIn] + scan.models
        skipped = scan.skipped
        #if DEBUG
        for (name, reason) in scan.skipped {
            print("[ModelRegistry] skipped \(name): \(reason)")
        }
        #endif
    }

    var activeModel: any ThumpModel {
        models.first { $0.descriptor.modelId == selectedId }
            ?? models.first { $0.descriptor.isDefault }
            ?? ModelFileLoader.loadBuiltIn()
    }
}
