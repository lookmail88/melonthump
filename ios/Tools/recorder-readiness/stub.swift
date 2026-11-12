import Foundation
// Minimal stand-in so the production RecorderReadiness.swift compiles as
// a macOS command-line tool (RecorderError's description reads L10n).
struct L10n {
    static var current: L10n { L10n() }
    func t(_ key: String) -> String { key }
}
