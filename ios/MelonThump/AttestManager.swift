import CryptoKit
import DeviceCheck
import Foundation

/// App Attest key lifecycle (design doc §5/§6): generate → enroll →
/// assert, keyed to the selected backend environment.
///
/// Everything here is fail-open: an unsupported device (simulator),
/// a failed enrollment or a failed assertion simply yields nil, and
/// the app behaves exactly like 1.0.0 — the version policy arrives
/// without the attested field and stats uploads wait for a later
/// launch. Attestation never blocks thumping.
///
/// Client-data convention (must match the server byte for byte):
/// enrollment hashes SHA-256(challenge); an assertion's client data
/// hash is SHA-256(challenge || SHA-256(payload)), where payload is
/// the exact request body — or, for the body-less policy GET, the
/// canonical request string "GET /api/v1/version/getclientversion?currentVersion=<v>".
actor AttestManager {
    static let shared = AttestManager()

    /// True on real hardware; false on the simulator, where App Attest
    /// does not exist. Nonisolated: reads only the system singleton.
    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// Headers the simulator sends instead of an assertion; only the
    /// dev backend honours them (design doc §5), prod never does.
    static let bypassHeaders = ["X-Attest-Bypass": "simulator"]

    private func defaultsKey(_ name: String, _ environment: ServerEnvironment) -> String {
        "attest.\(name).\(environment.rawValue)"
    }

    private func enrolledKeyId(environment: ServerEnvironment) -> String? {
        guard UserDefaults.standard.bool(forKey: defaultsKey("enrolled", environment)) else {
            return nil
        }
        return UserDefaults.standard.string(forKey: defaultsKey("keyId", environment))
    }

    /// Ensures this install has a key enrolled with the given backend.
    /// Returns the keyId when enrolled; nil on any failure.
    func ensureEnrolled(environment: ServerEnvironment, installId: UUID) async -> String? {
        guard Self.isSupported else { return nil }
        if let existing = enrolledKeyId(environment: environment) {
            return existing
        }
        do {
            let keyId: String
            if let stored = UserDefaults.standard.string(forKey: defaultsKey("keyId", environment)) {
                keyId = stored
            } else {
                keyId = try await DCAppAttestService.shared.generateKey()
                UserDefaults.standard.set(keyId, forKey: defaultsKey("keyId", environment))
            }
            let client = APIClient(environment: environment)
            let challengeB64 = try await client.fetchAttestChallenge()
            guard let challenge = Data(base64Encoded: challengeB64) else { return nil }
            let clientDataHash = Data(SHA256.hash(data: challenge))
            let attestation = try await DCAppAttestService.shared.attestKey(
                keyId, clientDataHash: clientDataHash)
            try await client.enrollAttestKey(
                keyId: keyId,
                attestationObjectB64: attestation.base64EncodedString(),
                challengeB64: challengeB64,
                installId: installId)
            UserDefaults.standard.set(true, forKey: defaultsKey("enrolled", environment))
            return keyId
        } catch {
            #if DEBUG
            print("[AttestManager] enrollment failed: \(error)")
            #endif
            return nil
        }
    }

    /// Builds the assertion headers for one request, or nil when this
    /// device cannot assert (unsupported / not enrolled / any error).
    func assertionHeaders(environment: ServerEnvironment, payload: Data) async -> [String: String]? {
        guard Self.isSupported,
              let keyId = enrolledKeyId(environment: environment) else {
            return nil
        }
        do {
            let client = APIClient(environment: environment)
            let challengeB64 = try await client.fetchAttestChallenge()
            guard let challenge = Data(base64Encoded: challengeB64) else { return nil }
            var hasher = SHA256()
            hasher.update(data: challenge)
            hasher.update(data: Data(SHA256.hash(data: payload)))
            let clientDataHash = Data(hasher.finalize())
            #if DEBUG
            // TEMPORARY DIAGNOSTIC (2026-10-24): disclose exactly what
            // is fed to generateAssertion so a rejected assertion can
            // be reproduced offline byte for byte.
            print("[AttestDiag] keyId=\(keyId) challenge=\(challengeB64) payloadSha256=\(SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()) payloadBytes=\(payload.count) clientDataHash=\(clientDataHash.map { String(format: "%02x", $0) }.joined())")
            #endif
            let assertion = try await DCAppAttestService.shared.generateAssertion(
                keyId, clientDataHash: clientDataHash)
            return [
                "X-Key-Id": keyId,
                "X-Assertion": assertion.base64EncodedString(),
                "X-Challenge": challengeB64,
            ]
        } catch {
            return nil
        }
    }
}
