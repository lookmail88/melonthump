import Foundation
import ImageIO
import Vision

// FIX12: Apple Vision's built-in classifier as a SOFT "is this a
// watermelon?" signal. On-device, no model download. Used twice:
//  A. capture-time hint (journey sheet confirmation, record page caption);
//  B. sample annotation sent with submit / send-updates.
// It never blocks a user action. Any error or missing result is "no
// opinion" (nil): no hint, and the field is left out of the upload.

enum WatermelonVision {
    /// Below this score a photo is flagged "doesn't look like a watermelon".
    static let watermelonHintThreshold = 0.20

    /// The Vision label whose confidence is the score.
    static let identifier = "watermelon"
    /// Photos are classified from a downscaled copy of about this size.
    static let maxPixelSize = 512

    /// True only for a real score below the threshold (nil = no opinion).
    static func isFlagged(_ score: Double?) -> Bool {
        guard let score else { return false }
        return score < watermelonHintThreshold
    }

    /// Score for encoded image bytes (JPEG / PNG / HEIC / WebP), computed
    /// on a background queue. nil on any error.
    static func score(data: Data) async -> Double? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return classify(source)
        }.value
    }

    /// Score for a stored photo file, computed on a background queue.
    static func score(url: URL) async -> Double? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return classify(source)
        }.value
    }

    /// Synchronous: call off the main thread only.
    private static func classify(_ source: CGImageSource) -> Double? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let results = request.results, !results.isEmpty else { return nil }
        let hit = results.first { $0.identifier == identifier }
        return Double(hit?.confidence ?? 0)
    }
}
