import Foundation

enum APIError: Error, LocalizedError {
    case invalidServerURL
    case badResponse(status: Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL"
        case .badResponse(let status):
            return "Server returned status \(status)"
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

/// Stateless HTTP client for the MelonThump server. Sendable-safe for Swift 6.
final class APIClient: Sendable {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Uploads a WAV tap recording and returns the ripeness analysis.
    func analyzeTap(audioURL: URL) async throws -> TapResult {
        let endpoint = baseURL.appendingPathComponent("api/v1/tap/analyze")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try multipartBody(boundary: boundary, fileURL: audioURL)
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(TapResult.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func multipartBody(boundary: String, fileURL: URL) throws -> Data {
        var body = Data()
        let filename = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
