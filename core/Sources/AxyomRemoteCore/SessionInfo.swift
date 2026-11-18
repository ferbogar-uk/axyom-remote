import Foundation

/// The exact model a session runs, read from the transcript (the provider's
/// init row carries it: Claude `claude-opus-4-5-…`, Cursor `Composer 2.5`).
public enum ModelInfo {
    /// The last model id the transcript mentions in a session-start/init row.
    public static func latest(in items: [TranscriptItem]) -> String? {
        for item in items.reversed() where item.direction == "output" {
            guard let d = item.raw.data(using: .utf8),
                  let v = try? JSONDecoder().decode(JSONValue.self, from: d) else { continue }
            let type = v["type"]?.string ?? ""
            let sub = v["subtype"]?.string ?? ""
            if (type == "system" && sub == "init") || type == "session_configured" || type == "thread.started" {
                if let m = v["model"]?.string, !m.isEmpty { return m }
            }
        }
        return nil
    }

    /// "claude-opus-4-5-20251101" -> "Opus 4.5"; "claude-code:sonnet" -> "Sonnet";
    /// "gpt-5.5" -> "GPT 5.5"; "Composer 2.5" stays.
    public static func display(_ raw: String?) -> String? {
        guard var m = raw?.trimmingCharacters(in: .whitespaces), !m.isEmpty else { return nil }
        if let colon = m.lastIndex(of: ":") { m = String(m[m.index(after: colon)...]) }
        let lower = m.lowercased()
        for family in ["opus", "sonnet", "haiku", "fable", "mythos"] where lower.contains(family) {
            // Version: the first run of 1-2 digit numbers after the family name (skip 8-digit dates).
            let afterFamily = lower.components(separatedBy: family).dropFirst().joined(separator: family)
            let numbers = afterFamily.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { $0.count <= 2 }
            let version = numbers.prefix(2).joined(separator: ".")
            let name = family.prefix(1).uppercased() + family.dropFirst()
            return version.isEmpty ? name : "\(name) \(version)"
        }
        if lower.hasPrefix("gpt-") { return "GPT " + m.dropFirst(4).replacingOccurrences(of: "-", with: " ") }
        if lower.hasPrefix("gemini") {
            return m.replacingOccurrences(of: "-", with: " ").split(separator: " ")
                .map { $0.first?.isNumber == true ? String($0) : $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return m.prefix(1).uppercased() + m.dropFirst()
    }
}

/// Effort levels the desktop knows (packages/runtime/src/ai/server/effortLevels.ts).
public enum EffortLevels {
    public static let all: [(key: String, label: String)] = [
        ("low", "Low"), ("medium", "Medium"), ("high", "High"), ("xhigh", "xHigh"), ("max", "Max"), ("ultra", "Ultra"),
    ]
}

/// What the agent is doing right now, for the animated status line
/// ("A correr um comando…"), from the newest output row.
public enum AgentActivity {
    public static func current(_ items: [TranscriptItem]) -> String {
        for item in items.reversed() {
            if item.direction == "input" { return "A pensar" }
            guard let d = item.raw.data(using: .utf8),
                  let v = try? JSONDecoder().decode(JSONValue.self, from: d) else { return "A escrever" }
            if let label = label(v) { return label }
        }
        return "A trabalhar"
    }

    static func label(_ v: JSONValue) -> String? {
        var names: [String] = []
        var types: [String] = []
        collect(v, depth: 0, names: &names, types: &types)
        if let tool = names.last { return toolLabel(tool) }
        let t = types.joined(separator: " ").lowercased()
        if t.contains("command") { return "A correr um comando" }
        if t.contains("thinking") || t.contains("reasoning") || t.contains("thought") { return "A pensar" }
        if t.contains("filechange") || t.contains("patch") { return "A editar ficheiros" }
        if t.contains("search") { return "A pesquisar" }
        if t.contains("assistant") || t.contains("text") || t.contains("message") { return "A escrever" }
        return nil
    }

    static func toolLabel(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("bash") || n.contains("shell") || n.contains("command") || n.contains("exec") || n.contains("terminal") { return "A correr um comando" }
        if n.contains("read") || n.contains("grep") || n.contains("glob") || n.contains("list") || n.contains("ls") { return "A ler ficheiros" }
        if n.contains("edit") || n.contains("write") || n.contains("patch") { return "A editar ficheiros" }
        if n.contains("web") || n.contains("fetch") || n.contains("search") { return "A pesquisar" }
        if n.contains("task") || n.contains("agent") { return "A delegar num subagente" }
        if n.contains("todo") { return "A planear" }
        return "A usar \(name)"
    }

    private static func collect(_ v: JSONValue, depth: Int, names: inout [String], types: inout [String]) {
        guard depth < 6 else { return }
        switch v {
        case .object(let o):
            if let t = o["type"]?.string {
                types.append(t)
                if t == "tool_use" || t == "tool_call" || t == "nimbalyst_tool_use", let n = o["name"]?.string ?? o["toolName"]?.string { names.append(n) }
            }
            for x in o.values { collect(x, depth: depth + 1, names: &names, types: &types) }
        case .array(let a):
            for x in a { collect(x, depth: depth + 1, names: &names, types: &types) }
        default: break
        }
    }
}

/// Short, human connection messages. Raw errors can carry the request URL with
/// the short-lived access token, so they are never shown.
public enum ConnectionMessage {
    public static func from(_ error: Error) -> String {
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "Sem ligação à internet"
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Sem ligação ao servidor"
            default: break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == -1009 { return "Sem ligação à internet" }
        return "Sem ligação ao servidor"
    }
}
