import Foundation

/// One bubble on the session screen.
public struct ChatLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var mine: Bool
    public var text: String
    /// A tool step of the agent ("Correu: git status"), shown small and grouped.
    public var isStep: Bool = false
    /// The raw thing behind a step (the exact command, path or notice), shown only when opened.
    public var detail: String?
    /// The change a file-edit step made, shown green/red when opened.
    public var diff: FileDiff?

    public init(id: String, mine: Bool, text: String, isStep: Bool = false, detail: String? = nil, diff: FileDiff? = nil) {
        self.id = id; self.mine = mine; self.text = text; self.isStep = isStep; self.detail = detail; self.diff = diff
    }
}

/// Turns the raw synced rows into what a person reads, following the desktop's
/// own parsers (packages/runtime/src/ai/server/transcript/parsers):
/// - Cursor / Grok (HeadlessAgentRawParser): streamed text and reasoning deltas
///   are dropped; the turn's text comes from `item.completed` or plain-text rows.
/// - Claude Code: `assistant` events carry `message.content` text blocks;
///   system, result, user/tool_result and stream events are not chat.
/// - Anything else: a row is shown only when it reads as prose, and JSON
///   bookkeeping (init, thinking, usage, deltas) is hidden.
/// Interactive prompts (permission, question, plan) are hidden here because
/// the screen shows them as cards.
public enum ChatLines {
    public static func build(_ items: [TranscriptItem], provider: String, includeSteps: Bool = false) -> [ChatLine] {
        var out: [ChatLine] = []
        for item in items where !item.hidden {
            let mine = item.direction == "input"
            // Notices the desktop injects as input rows (a background task finished, …):
            // one quiet step line, never a bubble full of paths and ids.
            if mine, let notice = Notices.summary(item.raw) {
                if includeSteps, !(out.last.map { $0.isStep && $0.text == notice } ?? false) {
                    out.append(ChatLine(id: item.id, mine: false, text: notice, isStep: true, detail: Notices.detail(item.raw)))
                }
                continue
            }
            if let text = mine ? userText(item) : agentText(item, provider: provider) {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // The same text twice in a row (a final event repeating its stream) is one message.
                if !clean.isEmpty, !(out.last.map { $0.mine == mine && $0.text == clean && !$0.isStep } ?? false) {
                    out.append(ChatLine(id: item.id, mine: mine, text: clean))
                }
            }
            // Tool steps come after the text of the same event (the agent says, then does).
            if includeSteps && !mine, let v = json(item.raw) {
                for (i, s) in Steps.detailed(v).enumerated() where !(out.last.map { $0.isStep && $0.text == s.text } ?? false) {
                    out.append(ChatLine(id: "\(item.id)#\(i)", mine: false, text: s.text, isStep: true, detail: s.detail, diff: s.diff))
                }
            }
        }
        return out
    }

    static func json(_ raw: String) -> JSONValue? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") || t.hasPrefix("["), let d = t.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: d)
    }

    static func userText(_ item: TranscriptItem) -> String? {
        guard let value = json(item.raw) else { return isReminder(item.raw) ? nil : item.raw }
        if let type = value["type"]?.string, promptTypes.contains(type) { return nil }
        // Claude Code tool results come back as "user" rows; they are not the person talking.
        if value["type"]?.string == "user" { return nil }
        for key in ["prompt", "text", "content", "message"] {
            if let s = value[key]?.string, !s.isEmpty { return isReminder(s) ? nil : s }
        }
        return nil
    }

    /// System reminders the desktop injects as input rows are not the person talking.
    static func isReminder(_ s: String) -> Bool {
        s.contains("<SYSTEM_REMINDER>") || s.contains("<system-reminder>")
    }

    static let promptTypes: Set<String> = [
        "permission_request", "permission_response",
        "ask_user_question_request", "ask_user_question_response",
        "exit_plan_mode_request", "exit_plan_mode_response",
        "git_commit_request", "git_commit_response",
        "request_user_input_request", "request_user_input_response",
        "git_commit_proposal", "git_commit_proposal_response",
        "nimbalyst_tool_use", "nimbalyst_tool_result",
    ]

    static func agentText(_ item: TranscriptItem, provider: String) -> String? {
        guard let value = json(item.raw) else { return item.raw }    // plain text = the agent's words
        let type = value["type"]?.string ?? ""
        if promptTypes.contains(type) { return nil }
        if type == "item.completed" { return completedText(value["item"]) }
        // Codex app-server envelope: { method: "item/completed", params: { item } }.
        if let method = value["method"]?.string {
            return method == "item/completed" ? completedText(value["params"]?["item"]) : nil
        }

        if provider.hasPrefix("claude") {
            guard type == "assistant" else { return nil }
            return blocksText(value["message"]?["content"])
        }
        if provider.hasPrefix("cursor") || provider.hasPrefix("grok") {
            return nil   // deltas and tool events; the turn's text arrives in item.completed
        }
        // Other providers: keep only events that look like a finished assistant message.
        let noise = ["delta", "thinking", "reasoning", "thought", "system", "init", "usage", "started", "result", "tool", "status", "error"]
        if noise.contains(where: { type.lowercased().contains($0) }) { return nil }
        if type == "assistant" || type == "message" || type == "assistant_message" || type == "agent_message" {
            return blocksText(value["message"]?["content"]) ?? blocksText(value["content"]) ?? value["text"]?.string
        }
        return nil
    }

    /// `item.completed`: Codex/Cursor shapes, `{type:"message", content:[{type:"output_text", text}]}` or `{type:"agent_message", text}`.
    static func completedText(_ item: JSONValue?) -> String? {
        guard let item else { return nil }
        let kind = item["type"]?.string ?? ""
        let k = kind.lowercased()
        if k.contains("reasoning") || k.contains("tool") || k.contains("command") || k.contains("filechange") || k.contains("todo") { return nil }
        if let role = item["role"]?.string, role != "assistant" { return nil }
        return blocksText(item["content"]) ?? item["text"]?.string
    }

    /// Text of `[{type:"text"|"output_text", text}]`, or a plain string.
    static func blocksText(_ v: JSONValue?) -> String? {
        switch v {
        case .string(let s)?: return s
        case .array(let a)?:
            let parts = a.compactMap { b -> String? in
                let t = b["type"]?.string ?? "text"
                guard t == "text" || t == "output_text" else { return nil }
                return b["text"]?.string
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        default: return nil
        }
    }
}
