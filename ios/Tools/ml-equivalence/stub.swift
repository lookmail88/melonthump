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
// LocalAnalyzer's error descriptions go through the app's L10n; the
// harness only needs the symbol, so it returns the key.
struct L10n {
    static var current: L10n { L10n() }
    func t(_ key: String) -> String { key }
}
