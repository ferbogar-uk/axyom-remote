import Foundation

/// One-line summaries of what the agent did with its tools, in Portuguese,
/// for the collapsed "passos" rows of the chat (like Claude's "Ran a command").
public enum Steps {
    /// One step: what a person reads, and the raw command/path behind it.
    public struct Step: Equatable, Sendable {
        public let text: String
        public let detail: String?
        public let diff: FileDiff?
        public init(_ text: String, detail: String? = nil, diff: FileDiff? = nil) { self.text = text; self.detail = detail; self.diff = diff }
    }

    public static func describe(_ v: JSONValue) -> [String] { detailed(v).map(\.text) }

    public static func detailed(_ v: JSONValue) -> [Step] {
        var out: [Step] = []
        // Codex exec / Cursor: item.completed with a command or file change.
        if v["type"]?.string == "item.completed", let s = item(v["item"]) { return [s] }
        // Codex app-server envelope.
        if v["method"]?.string == "item/completed", let s = item(v["params"]?["item"]) { return [s] }
        walk(v, depth: 0, into: &out)
        return out
    }

    static func item(_ item: JSONValue?) -> Step? {
        guard let item, let kind = item["type"]?.string?.lowercased() else { return nil }
        if kind.contains("command") {
            let cmd = item["command"]?.string ?? ""
            return Step(command(cmd, description: nil), detail: cmd.isEmpty ? nil : cmd)
        }
        if kind.contains("filechange") || kind.contains("file_change") {
            var paths: [String] = []
            if case .array(let changes)? = item["changes"] { paths = changes.compactMap { $0["path"]?.string } }
            var diff: FileDiff?
            if case .array(let changes)? = item["changes"], changes.count == 1,
               let p = changes[0]["path"]?.string, let d = changes[0]["diff"]?.string ?? changes[0]["unified_diff"]?.string {
                diff = FileDiff.unified(path: p, d)
            }
            let base = paths.isEmpty ? "Editou ficheiros" : "Editou " + paths.map(file).joined(separator: ", ")
            return Step(diff.map { $0.counts.isEmpty ? base : base + " · " + $0.counts } ?? base,
                        detail: paths.isEmpty ? nil : paths.joined(separator: "\n"), diff: diff)
        }
        if kind.contains("web_search") || kind.contains("websearch") {
            return Step("Pesquisou na web: " + short(item["query"]?.string ?? ""))
        }
        return nil
    }

    private static func walk(_ v: JSONValue, depth: Int, into out: inout [Step]) {
        guard depth < 6 else { return }
        switch v {
        case .object(let o):
            if let t = o["type"]?.string, ["tool_use", "tool_call", "nimbalyst_tool_use"].contains(t),
               let name = o["name"]?.string ?? o["toolName"]?.string {
                out.append(toolStep(name, o["input"] ?? o["args"] ?? o["arguments"]))
                return
            }
            for x in o.values { walk(x, depth: depth + 1, into: &out) }
        case .array(let a):
            for x in a { walk(x, depth: depth + 1, into: &out) }
        default: break
        }
    }

    public static func tool(_ name: String, _ input: JSONValue?) -> String { toolStep(name, input).text }

    static func toolStep(_ name: String, _ input: JSONValue?) -> Step {
        let n = name.lowercased()
        let path = input?["file_path"]?.string ?? input?["path"]?.string ?? input?["notebook_path"]?.string
        if n.contains("bash") || n.contains("shell") || n.contains("command") || n.contains("terminal") || n.contains("start_process") {
            let cmd = input?["command"]?.string ?? input?["cmd"]?.string ?? ""
            return Step(command(cmd, description: input?["description"]?.string), detail: cmd.isEmpty ? nil : cmd)
        }
        if n.contains("websearch") || n.contains("web_search") { return Step("Pesquisou na web: " + short(input?["query"]?.string ?? "")) }
        if n.contains("webfetch") || n.contains("fetch") || n.contains("navigate") {
            let url = input?["url"]?.string ?? ""
            return Step("Abriu " + (URL(string: url)?.host ?? "uma página"), detail: url.isEmpty ? nil : url)
        }
        if n.contains("screenshot") { return Step("Tirou uma captura de ecrã") }
        if n.contains("list_directory") || n.contains("list_dir") || n == "ls" {
            return Step("Viu a pasta " + (path.map(file) ?? ""), detail: path)
        }
        if let diff = editDiff(n, input, path) {
            let verb = diff.removed == 0 && (n.contains("write") || n.contains("create")) ? "Criou " : "Editou "
            let text = verb + file(diff.path) + (diff.counts.isEmpty ? "" : " · " + diff.counts)
            return Step(text, detail: path, diff: diff)
        }
        return Step(toolText(n, name, input, path), detail: path)
    }

    /// Claude Edit (old_string/new_string), MultiEdit (edits[]), Write (content),
    /// Desktop Commander edit_block (old_string/new_string) and write_file (content).
    static func editDiff(_ n: String, _ input: JSONValue?, _ path: String?) -> FileDiff? {
        guard let input, let path, n.contains("edit") || n.contains("write") || n.contains("create") else { return nil }
        if let old = input["old_string"]?.string, let new = input["new_string"]?.string {
            return FileDiff.edit(path: path, old: old, new: new)
        }
        if case .array(let edits)? = input["edits"] {
            let parts = edits.compactMap { e -> FileDiff? in
                guard let old = e["old_string"]?.string, let new = e["new_string"]?.string else { return nil }
                return FileDiff.edit(path: path, old: old, new: new)
            }
            return parts.isEmpty ? nil : FileDiff.merge(path: path, parts)
        }
        if let content = input["content"]?.string { return FileDiff.created(path: path, content: content) }
        return nil
    }

    private static func toolText(_ n: String, _ name: String, _ input: JSONValue?, _ path: String?) -> String {
        if n == "read" || n.contains("read_file") || n.contains("read_multiple") || n.hasSuffix("read") { return "Leu " + (path.map(file) ?? "ficheiros") }
        if n.contains("edit") || n.contains("write") || n.contains("patch") { return "Editou " + (path.map(file) ?? "um ficheiro") }
        if n.contains("grep") || n.contains("glob") || n.contains("search_files") {
            return "Procurou no código: " + short(input?["pattern"]?.string ?? input?["query"]?.string ?? "")
        }
        if n == "task" || n.contains("agent") { return "Delegou: " + short(input?["description"]?.string ?? "uma tarefa") }
        if n.contains("todo") { return "Atualizou a lista de tarefas" }
        if n.hasPrefix("mcp__") || n.contains("plugin") {
            // mcp__server__tool_name → "Usou tool name (server)"; plugin ids are never shown.
            let last = name.components(separatedBy: "__").last ?? name
            let toolName = last.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            return "Usou " + toolName
        }
        return "Usou " + name
    }

    /// A shell command in plain Portuguese. The exact command stays in `detail`.
    public static func command(_ raw: String, description: String?) -> String {
        let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The last meaningful command of a chain (`cd x && git status`) says what it was for.
        let parts = cmd.components(separatedBy: CharacterSet(charactersIn: "&;|\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("cd ") && !$0.lowercased().hasPrefix("set ") }
        let lower = parts.joined(separator: " ").lowercased()
        func has(_ words: String...) -> Bool { words.contains { lower.contains($0) } }
        let rules: [(Bool, String)] = [
            (has("test", "vitest", "jest", "pytest", "xctest", "swift test"), "Correu os testes"),
            (has("build", "tsc ", "compile", "xcodebuild"), "Compilou o projeto"),
            (has("git commit"), "Fez um commit"),
            (has("git push"), "Enviou para o GitHub"),
            (has("git pull", "git fetch", "git clone"), "Atualizou do GitHub"),
            (has("git diff"), "Viu as alterações"),
            (has("git log"), "Viu o histórico do git"),
            (has("git status", "git branch"), "Viu o estado do git"),
            (has("gh run", "gh pr", "gh api"), "Consultou o GitHub"),
            (has("install", "npm i ", "pnpm add", "pip "), "Instalou dependências"),
            (has("logs", ".log", "get-winevent", "journalctl"), "Viu os registos"),
            (has("grep ", "rg ", "select-string", "findstr", "start_search"), "Procurou no código"),
            (has("cat ", "head ", "tail ", "get-content", "type ", "sed -n", "less "), "Leu ficheiros"),
            (lower.hasPrefix("ls") || has(" ls ", "dir ", "get-childitem", "find ", "tree"), "Viu pastas e ficheiros"),
            (has("curl ", "wget ", "invoke-webrequest"), "Pediu uma página web"),
            (has("mkdir", "new-item"), "Criou pastas"),
            (has("rm ", "del ", "remove-item"), "Apagou ficheiros"),
            (has("cp ", "mv ", "copy-item", "move-item"), "Moveu ou copiou ficheiros"),
        ]
        if let hit = rules.first(where: { $0.0 }) { return hit.1 }
        if let d = description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { return short(d) }
        return cmd.isEmpty ? "Correu um comando" : "Correu um comando"
    }

    static func file(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    static func short(_ s: String) -> String {
        let line = s.split(separator: "\n").first.map(String.init) ?? s
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 70 ? String(trimmed.prefix(70)) + "…" : trimmed
    }
}
