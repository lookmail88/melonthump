import Foundation
struct TapResult: Decodable {
    let dominantFrequencyHz: Double
    let spectralCentroidHz: Double
    let decayTimeMs: Double
    let verdict: String
    let confidence: Double
    let modelVersion: String
    let debugSummary: String?
}
