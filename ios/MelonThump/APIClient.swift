import Foundation

enum APIError: Error, LocalizedError {
    case badResponse(status: Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "Server returned status \(status)"
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

/// HTTP client for the MelonThump server. The server now only serves the
/// client version policy — tap analysis runs fully on-device
/// (see LocalAnalyzer). Sendable-safe for Swift 6.
final class APIClient: Sendable {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    convenience init(environment: ServerEnvironment) {
        self.init(baseURL: environment.baseURL)
    }

    /// Fetches the version policy, evaluated server-side against the
    /// supplied current version.
    func fetchClientVersion(currentVersion: String) async throws -> ClientVersion {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/version/getclientversion"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "currentVersion", value: currentVersion)]
        guard let url = components?.url else {
            throw APIError.badResponse(status: -1)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(ClientVersion.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
