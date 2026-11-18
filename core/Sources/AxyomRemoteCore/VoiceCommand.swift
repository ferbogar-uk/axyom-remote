import Foundation

/// What a spoken sentence asks AXYOM to do. Speech-to-text happens on the
/// phone (Apple's on-device recognizer, in the app); turning the text into an
/// action is plain logic and lives here, testable on Linux.
public enum VoiceIntent: Equatable, Sendable {
    /// Start a new session on the desktop.
    case newSession(agent: VoiceAgent?, project: String?, prompt: String)
    /// Answer the session that is waiting for you / currently open.
    case reply(prompt: String)
    case approve
    case deny
    case status
    case empty
}

public enum VoiceAgent: String, CaseIterable, Equatable, Sendable {
    case claude, codex, grok, gemini, opencode, cursor

    /// AXYOM provider id the desktop understands.
    public var providerId: String {
        switch self {
        case .claude: return "claude-code"
        case .codex: return "openai-codex"
        case .grok: return "grok-build"
        case .gemini: return "antigravity-gemini-agent"
        case .opencode: return "opencode"
        case .cursor: return "cursor-agent"
        }
    }

    var spokenForms: [String] {
        switch self {
        case .claude: return ["claude", "cloud", "clode"]          // common mis-hearings
        case .codex: return ["codex", "codecs", "códex"]
        case .grok: return ["grok", "groq", "grock"]
        case .gemini: return ["gemini", "jemini"]
        case .opencode: return ["opencode", "open code"]
        case .cursor: return ["cursor"]
        }
    }
}

public struct VoiceCommandParser: Sendable {
    /// Project names the user has (folder names), to recognise "no AXYOM", "in Hefesto".
    public var knownProjects: [String]

    public init(knownProjects: [String]) {
        self.knownProjects = knownProjects
    }

    public func parse(_ spoken: String) -> VoiceIntent {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        let n = Self.normalize(text)
        let words = n.split(separator: " ").map(String.init)

        if Self.matchesWhole(n, ["aprova", "aprovar", "aprovado", "sim aprova", "approve", "approved", "yes approve", "pode aprovar"]) { return .approve }
        if Self.matchesWhole(n, ["recusa", "recusar", "rejeita", "nao aprova", "deny", "reject", "no"]) { return .deny }
        if Self.containsAny(n, ["o que esta a acontecer", "o que esta acontecendo", "qual o estado", "como estao os agentes", "status", "whats happening", "what is happening"]) && words.count <= 8 {
            return .status
        }

        let agent = VoiceAgent.allCases.first { a in a.spokenForms.contains { Self.containsWord(n, Self.normalize($0)) } }
        let project = matchProject(n)
        let asksNew = Self.containsAny(n, ["nova sessao", "new session", "comeca", "começa", "start", "abre uma sessao", "lanca", "poe o", "poe a", "pede ao", "pede a", "manda o", "manda a", "ask "])
        if agent != nil || asksNew {
            return .newSession(agent: agent, project: project, prompt: text)
        }
        return .reply(prompt: text)
    }

    func matchProject(_ normalized: String) -> String? {
        // Longest name first so "AXYOM - AI Development OS" beats "AXYOM".
        let candidates = knownProjects.sorted { $0.count > $1.count }
        for p in candidates {
            let full = Self.normalize(p)
            if !full.isEmpty && normalized.contains(full) { return p }
            // Also accept the first word of a long folder name ("axyom" for "AXYOM - AI Development OS").
            if let first = full.split(separator: " ").first, first.count >= 4, Self.containsWord(normalized, String(first)) { return p }
        }
        return nil
    }

    /// Lowercase, no accents, punctuation to spaces, single spaces.
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let mapped = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func containsWord(_ text: String, _ word: String) -> Bool {
        (" " + text + " ").contains(" " + word + " ")
    }

    static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { (" " + text + " ").contains(" " + normalize($0) + " ") || text.hasPrefix(normalize($0) + " ") }
    }

    static func matchesWhole(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text == normalize($0) }
    }
}
