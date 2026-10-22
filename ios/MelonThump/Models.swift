import Foundation
import SwiftUI

/// Backend environments the app can talk to. The UI shows only the
/// display name ("Prod Server" / "Dev Server"), never the raw domain.
enum ServerEnvironment: String, CaseIterable, Identifiable {
    case prod
    case dev

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prod: return "Prod Server"
        case .dev: return "Dev Server"
        }
    }

    var baseURL: URL {
        switch self {
        case .prod: return URL(string: "https://melonthump.stephaniegao.me")!
        case .dev: return URL(string: "https://melonthump-dev.stephaniegao.me")!
        }
    }
}

/// Response from GET /api/v1/version/getclientversion — the only API the
/// app still calls; audio analysis runs fully on-device.
struct ClientVersion: Decodable {
    let platform: String
    let latestVersion: String
    let minSupportedVersion: String
    let updateAvailable: Bool
    let forceUpdate: Bool
    let updateUrl: String
}

/// Response from POST /api/v1/tap/analyze
struct TapResult: Decodable {
    let dominantFrequencyHz: Double
    let spectralCentroidHz: Double
    let decayTimeMs: Double
    let verdict: String
    let confidence: Double
    let modelVersion: String
    /// Local-only diagnostics (gate values from LocalAnalyzer),
    /// shown in small print on the result screen; absent in any
    /// server-shaped payload.
    let debugSummary: String?
}

enum Ripeness: String {
    case unripe = "UNRIPE"
    case ripe = "RIPE"
    case overripe = "OVERRIPE"
    case unknown = "UNKNOWN"

    init(verdict: String) {
        self = Ripeness(rawValue: verdict) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .unripe: return "Not ripe yet"
        case .ripe: return "Ripe — enjoy!"
        case .overripe: return "Overripe"
        case .unknown: return "Unknown"
        }
    }

    var emoji: String {
        switch self {
        case .unripe: return "🟡"
        case .ripe: return "🟢"
        case .overripe: return "🟤"
        case .unknown: return "⚪️"
        }
    }

    var color: Color {
        switch self {
        case .unripe: return .yellow
        case .ripe: return .green
        case .overripe: return .brown
        case .unknown: return .gray
        }
    }

    /// Stephanie's cat for this verdict (asset catalog name).
    var catAsset: String {
        switch self {
        case .unripe: return "CatLeft"
        case .ripe: return "CatGray"
        case .overripe: return "CatOrange"
        case .unknown: return "CatLeft"
        }
    }

    /// Accent color from Stephanie's palette, per verdict.
    var accent: Color {
        switch self {
        case .unripe: return Color(red: 0.66, green: 0.54, blue: 0.06)   // #A8890F
        case .ripe: return MelonTheme.deepGreen
        case .overripe: return Color(red: 0.66, green: 0.44, blue: 0.23) // #A9713B
        case .unknown: return .gray
        }
    }

    /// Screen background tint per verdict (home/analyzing use MelonTheme.background).
    var screenTint: Color {
        switch self {
        case .unripe: return Color(red: 0.83, green: 0.89, blue: 0.64)   // #D3E2A4
        case .ripe: return MelonTheme.background
        case .overripe: return Color(red: 0.88, green: 0.84, blue: 0.69) // #E0D6B0
        case .unknown: return MelonTheme.background
        }
    }

    /// One-line encouragement under the verdict, per Stephanie's design tone.
    var tagline: String {
        switch self {
        case .unripe: return "That thump sounds too high and hollow.\nGive this melon a few more days."
        case .ripe: return "Sweet, juicy and ready to cut.\nThe cats approve."
        case .overripe: return "That thump sounds deep and dull.\nEat it today — or blend it into juice!"
        case .unknown: return "That thump was hard to read.\nTry thumping again, a little closer."
        }
    }
}

/// Stephanie's palette, sampled from her original Canva export.
enum MelonTheme {
    static let background = Color(red: 0.75, green: 0.88, blue: 0.65)    // #BEE0A7
    static let deepGreen = Color(red: 0.25, green: 0.38, blue: 0.11)     // #41621B
    static let buttonGreen = Color(red: 0.24, green: 0.42, blue: 0.12)   // #3E6B1E
    static let cream = Color(red: 1.00, green: 0.98, blue: 0.93)         // #FFF9EE
    static let ink = Color(red: 0.18, green: 0.27, blue: 0.13)           // #2E4420
    static let inkSoft = Color(red: 0.35, green: 0.45, blue: 0.31)       // #5A7350
    static let recordRed = Color(red: 0.89, green: 0.28, blue: 0.24)     // #E2483D
}
