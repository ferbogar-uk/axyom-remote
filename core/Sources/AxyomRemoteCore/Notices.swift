import Foundation

/// Text the desktop or the agent's harness injects into the conversation as an
/// input row (a background task finished, a subagent report, …). The phone
/// shows one quiet line instead of the raw block of ids, paths and commands.
public enum Notices {
    /// One Portuguese line, or nil when the row is not such a notice.
    public static func summary(_ raw: String) -> String? {
        let s = text(raw)
        let markers = ["<task-notification>", "Continue the work that was waiting on them",
                       "SubagentHandback", "[SYSTEM NOTIFICATION", "Background command", "<task-id>"]
        guard markers.contains(where: { s.contains($0) }) else { return nil }
        let names = quotedTasks(s)
        let failed = s.contains("failed") || s.contains("(exit code 1")
        let verb = failed ? "falhou" : "terminou"
        if names.isEmpty { return "Tarefa em segundo plano " + verb }
        if names.count == 1 { return "Tarefa em segundo plano \(verb): \(names[0])" }
        return "\(names.count) tarefas em segundo plano terminaram: " + names.prefix(3).joined(separator: ", ")
    }

    /// The raw notice, for when the step is opened.
    public static func detail(_ raw: String) -> String {
        let s = text(raw)
        return s.count > 1500 ? String(s.prefix(1500)) + "…" : s
    }

    /// `"Analisar repositório AXYOM" completed` → task names that are words, not commands.
    static func quotedTasks(_ s: String) -> [String] {
        var out: [String] = []
        let pattern = #""([^"\n]{3,80})"\s+(completed|failed)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            // Skip shell commands quoted the same way ("cd …", pipes, paths).
            let looksLikeCommand = name.contains("|") || name.contains("&&") || name.contains("/") || name.contains("\\")
                || name.hasPrefix("cd ") || name.hasPrefix("$")
            if !looksLikeCommand, !out.contains(name) { out.append(name) }
        }
        return out
    }

    /// The text of an input row: `{ prompt | text | content | message }` or the raw string.
    static func text(_ raw: String) -> String {
        if let v = ChatLines.json(raw) {
            for key in ["prompt", "text", "content", "message"] {
                if let s = v[key]?.string, !s.isEmpty { return s }
            }
        }
        return raw
    }
}
