import Foundation
// Minimal stand-ins so the production LocalAnalyzer.swift + ModelFile.swift
// compile as a macOS command-line tool (no UIKit/SwiftUI app target).
struct TapResult: Decodable {
    let dominantFrequencyHz: Double
    let spectralCentroidHz: Double
    let decayTimeMs: Double
    let verdict: String
    let confidence: Double
    let modelVersion: String
    let debugSummary: String?
}
struct L10n {
    static var current: L10n { L10n() }
    func t(_ key: String) -> String { key }
}
