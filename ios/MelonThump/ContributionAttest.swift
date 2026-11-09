import CryptoKit
import Foundation

// MARK: - App Attest payloads for /api/v1/contributions/** (2.0)
//
// Must match the server's ContributionAttestGate byte for byte. The
// "payload" built here is what AttestManager.assertionHeaders hashes:
// clientDataHash = SHA-256(challenge || SHA-256(payload)), exactly as
// for the invite / stats / version-policy calls.
//
//   JSON POST       payload = the exact request body bytes
//   GET / DELETE    payload = "<METHOD> <path>?<raw query>"  ("?" omitted
//                             when there is no query)
//   multipart POST  payload = "POST <path>" then, for each part in wire
//                             order, "\n<part name>:<lowercase hex
//                             SHA-256 of the part bytes>"; no trailing
//                             newline. The query string is NOT covered
//                             (the server uses getRequestURI()), so every
//                             multipart call here carries its contributorId
//                             inside the covered meta part.
//
// Pure Foundation + CryptoKit on purpose: ios/Tools/contrib-attest
// compiles this file on macOS and checks it against the server's Java
// implementation.

enum ContributionAttest {
    /// Canonical string for a body-less request.
    static func bodilessPayload(method: String, path: String, rawQuery: String?) -> Data {
        var s = method + " " + path
        if let rawQuery, !rawQuery.isEmpty { s += "?" + rawQuery }
        return Data(s.utf8)
    }

    /// Canonical string for a multipart request, parts in wire order.
    static func multipartPayload(method: String = "POST", path: String, parts: [MultipartPart]) -> Data {
        Data(multipartCanonicalString(method: method, path: path, parts: parts).utf8)
    }

    static func multipartCanonicalString(method: String, path: String, parts: [MultipartPart]) -> String {
        var s = method + " " + path
        for part in parts {
            s += "\n" + part.name + ":" + hexSHA256(part.data)
        }
        return s
    }

    static func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// One multipart/form-data part. The body builder and the attest
/// payload both iterate the same array, so the covered order is the
/// wire order by construction.
struct MultipartPart: Sendable {
    let name: String
    let filename: String?
    let contentType: String
    let data: Data
}

enum MultipartBody {
    /// Encodes the parts in array order. Returns the body and the
    /// Content-Type header value.
    static func encode(_ parts: [MultipartPart], boundary: String = "MelonThump-\(UUID().uuidString)")
        -> (body: Data, contentType: String) {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        for part in parts {
            append("--\(boundary)\r\n")
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            append(disposition + "\r\n")
            append("Content-Type: \(part.contentType)\r\n\r\n")
            body.append(part.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}
