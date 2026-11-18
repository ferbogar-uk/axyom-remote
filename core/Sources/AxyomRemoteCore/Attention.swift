import Foundation

/// Decides which sessions just started waiting for the user, so the app can
/// raise a local notification once per wait (not on every index update).
public struct AttentionWatcher: Sendable {
    private var waiting: Set<String> = []
    private var primed = false

    public init() {}

    /// Feed the latest sessions; returns the ones that became "waiting for you"
    /// since the previous call. The first call only learns the current state.
    public mutating func update(_ sessions: [FleetSession]) -> [FleetSession] {
        let now = Set(sessions.filter { $0.hasPendingPrompt && !$0.isArchived }.map(\.id))
        defer { waiting = now; primed = true }
        guard primed else { return [] }
        return sessions.filter { now.contains($0.id) && !waiting.contains($0.id) }
    }
}

/// Decides which sessions just finished a turn (were working, now idle and not
/// waiting for you), for the "agent finished" notice. First call only learns.
public struct FinishWatcher: Sendable {
    private var working: Set<String> = []
    private var primed = false

    public init() {}

    public mutating func update(_ sessions: [FleetSession]) -> [FleetSession] {
        let now = Set(sessions.filter { $0.isExecuting && !$0.isArchived }.map(\.id))
        defer { working = now; primed = true }
        guard primed else { return [] }
        return sessions.filter { working.contains($0.id) && !now.contains($0.id) && !$0.hasPendingPrompt && !$0.isArchived }
    }
}

/// Text the phone reads aloud from the agent's side of a conversation.
public enum SpokenReply {
    /// Agent messages worth speaking: visible output that reads as prose, not raw JSON or tool noise.
    public static func lines(from items: [TranscriptItem], maxCharacters: Int = 600) -> [String] {
        items.compactMap { item in
            guard item.direction == "output", !item.hidden else { return nil }
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.hasPrefix("{"), !text.hasPrefix("[") else { return nil }
            guard text.count > maxCharacters else { return text }
            return String(text.prefix(maxCharacters)) + "…"
        }
    }
}
