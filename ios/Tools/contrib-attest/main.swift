import CryptoKit
import Foundation

// Contribution attest-payload harness (2.0 S5). Drives the PRODUCTION
// ios/MelonThump/ContributionAttest.swift on macOS.
//
//   vectors            print one line per fixed vector:
//                      <name> <base64 of the canonical payload bytes>
//                      (run.sh compares them with the server's Java)
//   live <base> <uuid> submit a multipart sample built by the production
//                      encoder to a QA server (simulator bypass), then
//                      check every per-part SHA-256 the server stored
//                      equals the digest in our canonical string, in
//                      wire order.

func bytes(_ n: Int, seed: UInt8) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) }) }

let meta = Data(#"{"contributorId":"0f8fad5b-d9cb-469f-a165-70867728950e","variety":"KIRIN"}"#.utf8)
let vectors: [(String, Data)] = [
    ("multipart_submit", ContributionAttest.multipartPayload(path: "/api/v1/contributions/samples", parts: [
        MultipartPart(name: "meta", filename: nil, contentType: "application/json", data: meta),
        MultipartPart(name: "appearance", filename: "a.jpg", contentType: "image/jpeg", data: bytes(2000, seed: 1)),
        MultipartPart(name: "appearance", filename: "b.jpg", contentType: "image/jpeg", data: bytes(1500, seed: 2)),
        MultipartPart(name: "recording", filename: "r.wav", contentType: "audio/wav", data: bytes(3000, seed: 3)),
        MultipartPart(name: "cutOpen", filename: "c.jpg", contentType: "image/jpeg", data: bytes(900, seed: 4)),
    ])),
    ("multipart_append", ContributionAttest.multipartPayload(path: "/api/v1/contributions/samples/42/parts", parts: [
        MultipartPart(name: "meta", filename: nil, contentType: "application/json", data: meta),
        MultipartPart(name: "cutOpen", filename: "c.jpg", contentType: "image/jpeg", data: bytes(900, seed: 4)),
    ])),
    ("multipart_empty_part_list", ContributionAttest.multipartPayload(path: "/api/v1/contributions/samples", parts: [])),
    ("get_status", ContributionAttest.bodilessPayload(method: "GET", path: "/api/v1/contributions/status",
                                                       rawQuery: "contributorId=0f8fad5b-d9cb-469f-a165-70867728950e")),
    ("delete_sample", ContributionAttest.bodilessPayload(method: "DELETE", path: "/api/v1/contributions/samples/7",
                                                          rawQuery: "contributorId=0f8fad5b-d9cb-469f-a165-70867728950e")),
    ("get_no_query", ContributionAttest.bodilessPayload(method: "GET", path: "/api/v1/contributions/samples", rawQuery: nil)),
]

let args = CommandLine.arguments
if args.count >= 2 && args[1] == "vectors" {
    for (name, data) in vectors { print(name, data.base64EncodedString()) }
    exit(0)
}

guard args.count == 4, args[1] == "live", let base = URL(string: args[2]) else {
    print("usage: harness vectors | live <base-url> <approved-contributor-uuid>")
    exit(2)
}
let contributor = args[3].lowercased()
let parts = [
    MultipartPart(name: "meta", filename: nil, contentType: "application/json",
                  data: Data(#"{"contributorId":"\#(contributor)","variety":"SEEDLESS","weightGrams":4200,"weightProvenance":"SCALE_MEASURED","feedback":{"bandTruth":"RIPE","score":88,"tasteTags":["CRISP","SWEET"]}}"#.utf8)),
    MultipartPart(name: "appearance", filename: "a1.jpg", contentType: "image/jpeg", data: bytes(4000, seed: 11)),
    MultipartPart(name: "appearance", filename: "a2.jpg", contentType: "image/jpeg", data: bytes(3500, seed: 12)),
    MultipartPart(name: "recording", filename: "recording.wav", contentType: "audio/wav", data: bytes(6000, seed: 13)),
    MultipartPart(name: "cutOpen", filename: "cutOpen.jpg", contentType: "image/jpeg", data: bytes(2500, seed: 14)),
]
let canonical = ContributionAttest.multipartCanonicalString(method: "POST", path: "/api/v1/contributions/samples", parts: parts)
let (body, contentType) = MultipartBody.encode(parts)
var request = URLRequest(url: base.appendingPathComponent("api/v1/contributions/samples"))
request.httpMethod = "POST"
request.setValue(contentType, forHTTPHeaderField: "Content-Type")
request.setValue("simulator", forHTTPHeaderField: "X-Attest-Bypass")
request.httpBody = body
let sem = DispatchSemaphore(value: 0)
nonisolated(unsafe) var status = -1
nonisolated(unsafe) var responseData = Data()
URLSession.shared.dataTask(with: request) { data, response, _ in
    status = (response as? HTTPURLResponse)?.statusCode ?? -1
    responseData = data ?? Data()
    sem.signal()
}.resume()
sem.wait()
print("POST /api/v1/contributions/samples ->", status)
struct FileView: Decodable { let part: String; let sha256: String }
struct Detail: Decodable { let id: Int64; let complete: Bool; let files: [FileView] }
guard status == 201, let detail = try? JSONDecoder().decode(Detail.self, from: responseData) else {
    print(String(data: responseData, encoding: .utf8) ?? "")
    exit(1)
}
// Canonical lines after the first: "<name>:<hex>" in wire order. The
// server lists files by storage order (appearance…, recording, cut_open),
// which is the wire order of the file parts we sent.
let lines = canonical.split(separator: "\n").dropFirst().map(String.init)
let fileLines = lines.filter { !$0.hasPrefix("meta:") }
let serverParts = detail.files.map { f -> String in
    let name = ["APPEARANCE": "appearance", "RECORDING": "recording", "CUT_OPEN": "cutOpen"][f.part] ?? f.part
    return "\(name):\(f.sha256)"
}
var fails = 0
print("sample", detail.id, "complete:", detail.complete)
for (i, line) in fileLines.enumerated() {
    let ok = i < serverParts.count && serverParts[i] == line
    if !ok { fails += 1 }
    print(ok ? "  ✓" : "  ✗", line, ok ? "" : "server: \(i < serverParts.count ? serverParts[i] : "-")")
}
if serverParts.count != fileLines.count { fails += 1; print("  ✗ file count", serverParts.count, "vs", fileLines.count) }
if !detail.complete { fails += 1; print("  ✗ expected a complete sample") }
print(fails == 0 ? "LIVE: all part digests match the server" : "LIVE: \(fails) mismatches")
exit(fails == 0 ? 0 : 1)
