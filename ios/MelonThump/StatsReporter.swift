import Foundation

/// Anonymous usage events (design doc §3.3/§6): analysis verdicts and
/// the ad lifecycle, doubling as our own ledger to reconcile against
/// AdMob. Events sit in a persistent on-device queue and flush in
/// attested batches on launch, at 20 queued events, and on entering
/// the background. Statistics degrade; the user experience never does.
actor StatsReporter {
    static let shared = StatsReporter()

    struct Event: Codable {
        var eventId: UUID
        var type: String
        /// Client occurrence time, epoch milliseconds (UTC).
        var clientTs: Int64
        var verdict: String?
        var slot: String?
        var unitSource: String?
        var errorCode: Int?
    }

    private struct UploadBody: Encodable {
        var installId: UUID
        var sessionId: UUID
        var events: [Event]
        var appVersion: String
        var channel: String
    }

    /// Logical ad slot name — never a real ad unit ID (design doc §3.3).
    static let rewardedSlot = "rewarded_main"
    private static let queueCap = 500
    private static let flushThreshold = 20

    private let sessionId = UUID()
    private var queue: [Event] = []
    private var loaded = false
    private var flushing = false

    /// Anonymous install identity (design doc §6): a first-launch UUID
    /// in UserDefaults — deliberately NOT Keychain, so deleting the
    /// app resets the identity; statistics must not survive uninstall.
    static var installId: UUID {
        if let raw = UserDefaults.standard.string(forKey: "stats.installId"),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: "stats.installId")
        return uuid
    }

    /// The backend the app is currently pointed at (same AppStorage
    /// key the version gate's picker writes).
    static var environment: ServerEnvironment {
        ServerEnvironment(rawValue: UserDefaults.standard.string(forKey: "serverEnvironment") ?? "") ?? .prod
    }

    // MARK: - Recording

    func recordAnalysis(verdict: String) {
        record(Event(eventId: UUID(), type: "analysis_completed",
                     clientTs: Self.nowMillis(), verdict: verdict,
                     slot: nil, unitSource: nil, errorCode: nil))
    }

    func recordAdRequested(unitSource: String) {
        record(Event(eventId: UUID(), type: "ad_requested",
                     clientTs: Self.nowMillis(), verdict: nil,
                     slot: Self.rewardedSlot, unitSource: unitSource, errorCode: nil))
    }

    func recordAdLoaded() {
        record(Event(eventId: UUID(), type: "ad_loaded",
                     clientTs: Self.nowMillis(), verdict: nil,
                     slot: Self.rewardedSlot, unitSource: nil, errorCode: nil))
    }

    func recordAdLoadFailed(errorCode: Int) {
        record(Event(eventId: UUID(), type: "ad_load_failed",
                     clientTs: Self.nowMillis(), verdict: nil,
                     slot: Self.rewardedSlot, unitSource: nil, errorCode: errorCode))
    }

    func recordAdShown() {
        record(Event(eventId: UUID(), type: "ad_shown",
                     clientTs: Self.nowMillis(), verdict: nil,
                     slot: Self.rewardedSlot, unitSource: nil, errorCode: nil))
    }

    func recordAdRewarded() {
        record(Event(eventId: UUID(), type: "ad_rewarded",
                     clientTs: Self.nowMillis(), verdict: nil,
                     slot: Self.rewardedSlot, unitSource: nil, errorCode: nil))
    }

    func recordAdDismissed() {
        record(Event(eventId: UUID(), type: "ad_dismissed",
                     clientTs: Self.nowMillis(), verdict: nil,
                     slot: Self.rewardedSlot, unitSource: nil, errorCode: nil))
    }

    private func record(_ event: Event) {
        loadIfNeeded()
        queue.append(event)
        if queue.count > Self.queueCap {
            queue.removeFirst(queue.count - Self.queueCap) // drop oldest
        }
        persist()
        if queue.count >= Self.flushThreshold {
            Task { await flush() }
        }
    }

    // MARK: - Upload

    /// Uploads the queued batch. 2xx clears it; a 400 means the server
    /// rejected the payload itself, so the batch is dropped rather
    /// than retried forever; anything else (offline, 401, 5xx) keeps
    /// the queue for the next trigger.
    func flush() async {
        loadIfNeeded()
        guard !flushing, !queue.isEmpty else { return }
        flushing = true
        defer { flushing = false }

        let environment = Self.environment
        let batch = queue
        guard let body = try? JSONEncoder().encode(
            UploadBody(installId: Self.installId, sessionId: sessionId, events: batch,
                       appVersion: AppIdentity.appVersion, channel: AppIdentity.channel))
        else { return }

        var headers = await AttestManager.shared.assertionHeaders(environment: environment, payload: body)
        if headers == nil && !AttestManager.isSupported {
            headers = AttestManager.bypassHeaders
        }
        guard let headers else { return } // cannot attest yet; keep queued

        do {
            let status = try await APIClient(environment: environment)
                .uploadStats(body: body, headers: headers)
            if (200..<300).contains(status) || status == 400 {
                let sentIds = Set(batch.map(\.eventId))
                queue.removeAll { sentIds.contains($0.eventId) }
                persist()
            }
        } catch {
            // Offline or transport error: keep the queue.
        }
    }

    // MARK: - Persistence

    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private var queueFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("stats-queue.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: queueFileURL),
           let events = try? JSONDecoder().decode([Event].self, from: data) {
            queue = events
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(queue) {
            try? data.write(to: queueFileURL, options: .atomic)
        }
    }
}
