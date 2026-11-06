import Foundation
import SwiftUI

/// Invites (design doc 1.2.0 §3): per-install invite code + link, the
/// invitee path (melonthump:// link or typed code), confirmation on the
/// invitee's first completed thump analysis, and once-only reward
/// claims into CreditWallet. The server confirms; the wallet stays
/// on-device. Every call is App Attest gated (simulator: dev bypass),
/// exactly like the stats upload, and every failure is silent except
/// where the user typed something and deserves an answer.
@MainActor
final class InviteManager: ObservableObject {
    static let shared = InviteManager()

    static let rewardCredits = 5
    static let cap = 10
    static let urlScheme = "melonthump"

    @Published private(set) var myCode: String?
    @Published private(set) var attributed: Bool
    @Published private(set) var firstThumpDone: Bool
    @Published private(set) var lastReward: Int?
    @Published private(set) var rewardedFriends: Int?

    private let defaults = UserDefaults.standard

    private enum Key {
        static func code(_ env: ServerEnvironment) -> String { "invite.code.\(env.rawValue)" }
        static let attributed = "invite.attributed"
        static let pendingCode = "invite.pendingCode"
        static let pendingSource = "invite.pendingSource"
        static let firstThumpDone = "invite.firstThumpDone"
        static let confirmPending = "invite.confirmPending"
        static let pendingClaimId = "invite.pendingClaimId"
    }

    enum AttributeResult: Equatable {
        case applied, malformed, unknownCode, ownCode, alreadyUsed, alreadyActive, network
    }

    private init() {
        attributed = defaults.bool(forKey: Key.attributed)
        firstThumpDone = defaults.bool(forKey: Key.firstThumpDone)
        myCode = defaults.string(forKey: Key.code(AppIdentity.effectiveEnvironment))
    }

    private var environment: ServerEnvironment { AppIdentity.effectiveEnvironment }

    /// Code entry stays reachable until the first thump completes
    /// (owner answer 2026-11-05); afterwards Invite goes straight to share.
    var offersCodeEntry: Bool { !firstThumpDone && !attributed }

    func shareURL(code: String) -> URL {
        environment.baseURL.appendingPathComponent("invite").appendingPathComponent(code)
    }

    func shareText(code: String, l: L10n) -> String {
        l.f("invite.shareText", code, shareURL(code: code).absoluteString)
    }

    // MARK: - Launch

    /// Launch work: retry a pending link attribution / confirmation and
    /// collect any rewards. Only installs that touched invites call out.
    func onLaunch(wallet: CreditWallet) async {
        if let pending = defaults.string(forKey: Key.pendingCode), !attributed, !firstThumpDone {
            _ = await attribute(code: pending, source: defaults.string(forKey: Key.pendingSource) ?? "link")
        }
        if defaults.bool(forKey: Key.confirmPending) {
            await confirm()
        }
        if myCode != nil || attributed {
            await claim(wallet: wallet)
        }
    }

    // MARK: - Inviter

    /// The install's invite code (issued by the server on first ask).
    func ensureCode() async -> String? {
        if let myCode { return myCode }
        struct Body: Encodable { let installId: UUID }
        struct Response: Decodable { let code: String }
        guard let (status, data) = await post("code", Body(installId: StatsReporter.installId)),
              status == 200, let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        myCode = response.code
        defaults.set(response.code, forKey: Key.code(environment))
        return response.code
    }

    // MARK: - Invitee

    /// melonthump://invite?code=XXXX — recorded as attribution only;
    /// nothing counts until the first thump completes.
    func handle(url: URL) async -> AttributeResult? {
        guard url.scheme == Self.urlScheme, url.host == "invite",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { return nil }
        guard offersCodeEntry else { return .alreadyActive }
        let result = await attribute(code: code, source: "link")
        if result == .network {
            defaults.set(code, forKey: Key.pendingCode)
            defaults.set("link", forKey: Key.pendingSource)
        }
        return result
    }

    static func normalize(_ raw: String) -> String? {
        let code = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        let alphabet = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return code.count == 8 && code.allSatisfy { alphabet.contains($0) } ? code : nil
    }

    func attribute(code raw: String, source: String) async -> AttributeResult {
        guard let code = Self.normalize(raw) else { return .malformed }
        if code == myCode { return .ownCode }
        struct Body: Encodable { let installId: UUID; let code: String; let source: String }
        guard let (status, data) = await post("attribute", Body(installId: StatsReporter.installId, code: code, source: source)) else {
            return .network
        }
        struct Reason: Decodable { let status: String }
        let reason = (try? JSONDecoder().decode(Reason.self, from: data))?.status
        let result: AttributeResult
        switch (status, reason) {
        case (200, _): result = .applied
        case (400, _): result = .malformed
        case (404, _): result = .unknownCode
        case (409, "self_invite"): result = .ownCode
        case (409, "already_active"): result = .alreadyActive
        case (409, _): result = .alreadyUsed
        default: return .network
        }
        defaults.removeObject(forKey: Key.pendingCode)
        if result == .applied {
            attributed = true
            defaults.set(true, forKey: Key.attributed)
        }
        return result
    }

    /// Called after every completed analysis: the first real one (non-
    /// UNKNOWN) is the invitee's confirmation event.
    func recordAnalysis(verdict: String, wallet: CreditWallet) async {
        guard verdict != Ripeness.unknown.rawValue, !firstThumpDone else { return }
        firstThumpDone = true
        defaults.set(true, forKey: Key.firstThumpDone)
        guard attributed else { return }
        defaults.set(true, forKey: Key.confirmPending)
        await confirm()
        await claim(wallet: wallet)
    }

    private func confirm() async {
        struct Body: Encodable { let installId: UUID }
        guard let (status, _) = await post("confirm", Body(installId: StatsReporter.installId)), status == 200 else {
            return // stays pending; retried next launch
        }
        defaults.removeObject(forKey: Key.confirmPending)
    }

    // MARK: - Rewards

    /// Claims all unclaimed rewards. The claimId is persisted until its
    /// credits are applied, so a lost response is retried with the same
    /// id (the server answers it idempotently) and nothing is counted twice.
    func claim(wallet: CreditWallet) async {
        let claimId = defaults.string(forKey: Key.pendingClaimId).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(claimId.uuidString, forKey: Key.pendingClaimId)
        struct Body: Encodable { let installId: UUID; let claimId: UUID }
        struct Response: Decodable { let claimId: UUID; let credits: Int }
        guard let (status, data) = await post("claim", Body(installId: StatsReporter.installId, claimId: claimId)),
              status == 200, let response = try? JSONDecoder().decode(Response.self, from: data),
              response.claimId == claimId else { return }
        if response.credits > 0, wallet.applyClaim(id: claimId, credits: response.credits) {
            lastReward = response.credits
        }
        defaults.removeObject(forKey: Key.pendingClaimId)
        await refreshProgress()
    }

    func refreshProgress() async {
        guard myCode != nil else { return }
        struct Body: Encodable { let installId: UUID }
        struct Response: Decodable { let rewardedInvites: Int }
        if let (status, data) = await post("status", Body(installId: StatsReporter.installId)), status == 200,
           let response = try? JSONDecoder().decode(Response.self, from: data) {
            rewardedFriends = response.rewardedInvites
        }
    }

    func clearLastReward() { lastReward = nil }

    // MARK: - Transport

    /// Attested POST to /api/v1/invite/<path>; nil on transport failure
    /// or when this device cannot attest yet.
    private func post<B: Encodable>(_ path: String, _ body: B) async -> (Int, Data)? {
        let env = environment
        guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
        _ = await AttestManager.shared.ensureEnrolled(environment: env, installId: StatsReporter.installId)
        var headers = await AttestManager.shared.assertionHeaders(environment: env, payload: bodyData)
        if headers == nil && !AttestManager.isSupported {
            headers = AttestManager.bypassHeaders
        }
        guard let headers else { return nil }
        return try? await APIClient(environment: env).postInvite(path: path, body: bodyData, headers: headers)
    }
}

// MARK: - Invite sheet

/// Shown from the Invite button while the user has not completed their
/// first thump: "Share my invite" / "I have a code". Afterwards the
/// button opens the share sheet directly.
struct InviteSheet: View {
    @ObservedObject var invites = InviteManager.shared
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @Environment(\.dismiss) private var dismiss
    @State private var codeInput = ""
    @State private var message: String?
    @State private var working = false
    @State private var shareItem: ShareItem?
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "gift")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(MelonTheme.buttonGreen)
                    .padding(.top, 20)
                Text(l.f("invite.blurb", InviteManager.rewardCredits, InviteManager.cap))
                    .font(.subheadline)
                    .foregroundColor(MelonTheme.inkSoft)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await share() }
                } label: {
                    Text(l.t("invite.share"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(MelonTheme.buttonGreen)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
                .disabled(working)

                if invites.offersCodeEntry {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l.t("invite.haveCode"))
                            .font(.headline)
                            .foregroundColor(MelonTheme.ink)
                        HStack {
                            TextField(l.t("invite.codePlaceholder"), text: $codeInput)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.body.monospaced())
                                .padding(12)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(12)
                            Button(l.t("invite.apply")) {
                                Task { await apply() }
                            }
                            .font(.headline)
                            .foregroundColor(MelonTheme.buttonGreen)
                            .disabled(working || codeInput.isEmpty)
                        }
                        Text(l.t("invite.codeHint"))
                            .font(.caption)
                            .foregroundColor(MelonTheme.inkSoft)
                    }
                    .padding(16)
                    .background(MelonTheme.cream)
                    .cornerRadius(20)
                }

                if let message {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(MelonTheme.deepGreen)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MelonTheme.background.ignoresSafeArea())
            .navigationTitle(l.t("invite.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l.t("common.done")) { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.text])
            }
        }
    }

    private func share() async {
        working = true
        defer { working = false }
        guard let code = await invites.ensureCode() else {
            message = l.t("invite.err.network")
            return
        }
        shareItem = ShareItem(text: invites.shareText(code: code, l: l))
    }

    private func apply() async {
        working = true
        defer { working = false }
        message = Self.message(for: await invites.attribute(code: codeInput, source: "code"), l: l)
    }

    static func message(for result: InviteManager.AttributeResult, l: L10n) -> String {
        switch result {
        case .applied: return l.f("invite.applied", InviteManager.rewardCredits)
        case .malformed: return l.t("invite.err.malformed")
        case .unknownCode: return l.t("invite.err.unknown")
        case .ownCode: return l.t("invite.err.self")
        case .alreadyUsed: return l.t("invite.err.taken")
        case .alreadyActive: return l.t("invite.err.active")
        case .network: return l.t("invite.err.network")
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

/// The system share sheet (Messages, WeChat, Mail, …).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
