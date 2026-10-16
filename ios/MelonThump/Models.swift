import Foundation
import SwiftUI

/// Response from POST /api/v1/tap/analyze
struct TapResult: Decodable {
    let dominantFrequencyHz: Double
    let spectralCentroidHz: Double
    let decayTimeMs: Double
    let verdict: String
    let confidence: Double
    let modelVersion: String
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
}
