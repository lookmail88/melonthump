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
    /// supplied current version. When assertion headers are supplied
    /// and verify, the response additionally carries the server-issued
    /// rewarded ad unit ID (1.1.0); without them it is exactly the
    /// 1.0.0 response.
    func fetchClientVersion(currentVersion: String, assertionHeaders: [String: String]? = nil) async throws -> ClientVersion {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/version/getclientversion"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "currentVersion", value: currentVersion)]
        guard let url = components?.url else {
            throw APIError.badResponse(status: -1)
        }
        var request = URLRequest(url: url)
        applyIdentityHeaders(&request)
        if let assertionHeaders {
            for (name, value) in assertionHeaders {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        // The launch splash waits for this check to conclude (it
        // shows at least 3 seconds); the request gets up to 10
        // seconds before the gate resolves it as fail-open.
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

    // MARK: - App Attest (1.1.0)

    private struct ChallengeResponse: Decodable {
        let challenge: String
        let expiresInSeconds: Int
    }

    private struct EnrollBody: Encodable {
        let keyId: String
        let attestationObject: String
        let challenge: String
        let installId: UUID
    }

    /// POST /api/v1/attest/challenge — a fresh, single-use challenge.
    func fetchAttestChallenge() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/attest/challenge"))
        applyIdentityHeaders(&request)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.requireSuccess(response)
        return try JSONDecoder().decode(ChallengeResponse.self, from: data).challenge
    }

    /// POST /api/v1/attest/enroll — registers an attested key with
    /// this backend (once per install per environment).
    func enrollAttestKey(keyId: String, attestationObjectB64: String,
                         challengeB64: String, installId: UUID) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/attest/enroll"))
        applyIdentityHeaders(&request)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EnrollBody(
            keyId: keyId, attestationObject: attestationObjectB64,
            challenge: challengeB64, installId: installId))
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.requireSuccess(response)
    }

    /// POST /api/v1/stats/events — uploads one attested batch. Returns
    /// the HTTP status (rather than throwing on non-2xx) so the caller
    /// can decide whether the queue keeps or drops the batch.
    func uploadStats(body: Data, headers: [String: String]) async throws -> Int {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/stats/events"))
        applyIdentityHeaders(&request)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse(status: -1)
        }
        return http.statusCode
    }

    /// Every request identifies the client build (X-App-Version).
    private func applyIdentityHeaders(_ request: inout URLRequest) {
        request.setValue(AppIdentity.appVersion, forHTTPHeaderField: "X-App-Version")
    }

    private static func requireSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse(status: http.statusCode)
        }
    }
}

/// Client identity reported to the server for operational analytics
/// (design doc section 3.4, 2026-10-24 addition): the app version goes
/// out on every request as the X-App-Version header, and the
/// distribution channel rides along in stats upload envelopes.
/// Analytics-grade only — the server never treats either as a
/// trust input.
enum AppIdentity {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Distribution channel, following the project's channel rules:
    /// Debug builds (installed from Xcode) are "xcode"; Release builds
    /// split by receipt — a sandbox receipt means TestFlight, a store
    /// receipt means the App Store.
    static var channel: String {
        #if DEBUG
        return "xcode"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "testflight"
        }
        return "appstore"
        #endif
    }

    /// The backend this build may talk to. Channel rule (tightened
    /// 2026-10-24): only Xcode (Debug) builds may use the stored
    /// server selection; TestFlight and App Store builds always use
    /// prod, whatever the picker was left on — a TestFlight install
    /// left on Dev once walled itself behind the dev update gate.
    static func resolvedEnvironment(stored: ServerEnvironment) -> ServerEnvironment {
        channel == "xcode" ? stored : .prod
    }

    /// The stored picker selection, resolved for this build.
    static var effectiveEnvironment: ServerEnvironment {
        let stored = ServerEnvironment(
            rawValue: UserDefaults.standard.string(forKey: "serverEnvironment") ?? "") ?? .prod
        return resolvedEnvironment(stored: stored)
    }
}
