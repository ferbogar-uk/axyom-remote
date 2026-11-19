import Foundation

/// What a push notification says. The server only knows the session id and
/// the kind (titles are encrypted), so the phone's notification extension
/// fills in the rest from a small context the app keeps (session titles,
/// agents, projects) and, when the server passes them, encrypted fields it can
/// decrypt with the pairing key (request #10).
public enum PushContent {
    public struct Entry: Codable, Equatable, Sendable {
        public var title: String
        public var provider: String
        public var project: String
        public init(title: String, provider: String, project: String) {
            self.title = title; self.provider = provider; self.project = project
        }
    }

    /// Shared with the extension through the Keychain.
    public struct Context: Codable, Equatable, Sendable {
        public var sessions: [String: Entry] = [:]
        public var seed: String?
        public var member: String?
        public init(sessions: [String: Entry] = [:], seed: String? = nil, member: String? = nil) {
            self.sessions = sessions; self.seed = seed; self.member = member
        }
    }

    public struct Text: Equatable, Sendable {
        public let title: String
        public let subtitle: String
        public let body: String
    }

    /// The newest sessions (at most `limit`), so the extension can name them.
    public static func context(from sessions: [FleetSession], seed: String?, member: String?, limit: Int = 80) -> Context {
        var map: [String: Entry] = [:]
        for s in sessions.sorted(by: { $0.lastActivity > $1.lastActivity }).prefix(limit) {
            map[s.id] = Entry(title: s.title, provider: s.provider, project: s.projectName)
        }
        return Context(sessions: map, seed: seed, member: member)
    }

    public static func agentName(_ provider: String) -> String {
        let p = provider.lowercased()
        if p.contains("claude") { return "Claude" }
        if p.contains("codex") || p.contains("openai") { return "Codex" }
        if p.contains("gemini") { return "Gemini" }
        if p.contains("cursor") { return "Cursor" }
        if p.contains("grok") { return "Grok" }
        if p.contains("opencode") { return "OpenCode" }
        return provider.isEmpty ? "Agente" : provider.prefix(1).uppercased() + provider.dropFirst()
    }

    /// Title: agent and conversation. Subtitle: what happened and the project.
    /// Body: the desktop's summary when there is one, else what to do next.
    public static func compose(kind: String, entry: Entry?, title decryptedTitle: String? = nil, summary: String? = nil) -> Text {
        let agent = entry.map { agentName($0.provider) } ?? "Agente"
        let conversation = (decryptedTitle ?? entry?.title)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let what: String
        let next: String
        switch kind {
        case "waiting":  what = "À tua espera"; next = "Precisa da tua resposta para continuar."
        case "finished": what = "Terminou";     next = "Toca para ver a resposta."
        case "error":    what = "Teve um erro"; next = "Toca para ver o que falhou."
        default:         what = "Novidades";    next = "Toca para abrir a conversa."
        }
        let title = [agent, conversation].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let project = entry?.project ?? ""
        let subtitle = project.isEmpty ? what : "\(what) · \(project)"
        var body = next
        if let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            body = s.count > 180 ? String(s.prefix(179)) + "…" : s
        }
        return Text(title: title.isEmpty ? "AXYOM" : title, subtitle: subtitle, body: body)
    }

    /// Fill a push from its payload: context entry for the session, plus any
    /// encrypted `encryptedTitle`/`titleIv` and `encryptedSummary`/`summaryIv`.
    public static func compose(payload: [String: String], context: Context) -> Text {
        let sessionId = payload["sessionId"] ?? ""
        var crypto: SyncCrypto?
        if let seed = context.seed, let member = context.member { crypto = try? SyncCrypto(seed: seed, memberId: member) }
        func open(_ c: String, _ iv: String) -> String? {
            guard let crypto, let c = payload[c], let iv = payload[iv] else { return nil }
            return try? crypto.decrypt(ciphertext: c, iv: iv)
        }
        return compose(kind: payload["kind"] ?? "update", entry: context.sessions[sessionId],
                       title: open("encryptedTitle", "titleIv"), summary: open("encryptedSummary", "summaryIv"))
    }
}
