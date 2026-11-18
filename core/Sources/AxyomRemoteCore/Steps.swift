import Foundation

/// One-line summaries of what the agent did with its tools, in Portuguese,
/// for the collapsed "passos" rows of the chat (like Claude's "Ran a command").
public enum Steps {
    public static func describe(_ v: JSONValue) -> [String] {
        var out: [String] = []
        // Codex exec / Cursor: item.completed with a command or file change.
        if v["type"]?.string == "item.completed", let s = item(v["item"]) { return [s] }
        // Codex app-server envelope.
        if v["method"]?.string == "item/completed", let s = item(v["params"]?["item"]) { return [s] }
        walk(v, depth: 0, into: &out)
        return out
    }

    static func item(_ item: JSONValue?) -> String? {
        guard let item, let kind = item["type"]?.string?.lowercased() else { return nil }
        if kind.contains("command") {
            return "Correu: " + short(item["command"]?.string ?? "um comando")
        }
        if kind.contains("filechange") || kind.contains("file_change") {
            var paths: [String] = []
            if case .array(let changes)? = item["changes"] { paths = changes.compactMap { $0["path"]?.string } }
            return paths.isEmpty ? "Editou ficheiros" : "Editou " + paths.map(file).joined(separator: ", ")
        }
        if kind.contains("web_search") || kind.contains("websearch") {
            return "Pesquisou: " + short(item["query"]?.string ?? "")
        }
        return nil
    }

    private static func walk(_ v: JSONValue, depth: Int, into out: inout [String]) {
        guard depth < 6 else { return }
        switch v {
        case .object(let o):
            if let t = o["type"]?.string, ["tool_use", "tool_call", "nimbalyst_tool_use"].contains(t),
               let name = o["name"]?.string ?? o["toolName"]?.string {
                out.append(tool(name, o["input"] ?? o["args"] ?? o["arguments"]))
                return
            }
            for x in o.values { walk(x, depth: depth + 1, into: &out) }
        case .array(let a):
            for x in a { walk(x, depth: depth + 1, into: &out) }
        default: break
        }
    }

    public static func tool(_ name: String, _ input: JSONValue?) -> String {
        let n = name.lowercased()
        let path = input?["file_path"]?.string ?? input?["path"]?.string ?? input?["notebook_path"]?.string
        if n.contains("bash") || n.contains("shell") || n.contains("command") || n.contains("terminal") {
            return "Correu: " + short(input?["command"]?.string ?? input?["cmd"]?.string ?? "um comando")
        }
        if n == "read" || n.contains("read_file") || n.hasSuffix("read") { return "Leu " + (path.map(file) ?? "um ficheiro") }
        if n.contains("edit") || n.contains("write") || n.contains("patch") { return "Editou " + (path.map(file) ?? "um ficheiro") }
        if n.contains("grep") || n.contains("glob") || n.contains("search_files") {
            return "Procurou: " + short(input?["pattern"]?.string ?? input?["query"]?.string ?? "")
        }
        if n.contains("websearch") || n.contains("web_search") { return "Pesquisou: " + short(input?["query"]?.string ?? "") }
        if n.contains("webfetch") || n.contains("fetch") { return "Abriu " + short(input?["url"]?.string ?? "uma página") }
        if n == "task" || n.contains("agent") { return "Delegou: " + short(input?["description"]?.string ?? "uma tarefa") }
        if n.contains("todo") { return "Atualizou a lista de tarefas" }
        return "Usou " + name
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
