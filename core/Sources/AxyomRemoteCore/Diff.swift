import Foundation

/// A small, readable diff for one file edit, shown when a step is opened:
/// green added lines, red removed lines, a little context.
public struct FileDiff: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case added, removed, context, gap }
    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let text: String
        public init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
    }

    public let path: String
    public let lines: [Line]
    public let added: Int
    public let removed: Int
    /// More changed lines exist than are shown.
    public let truncated: Bool

    public var counts: String {
        [added > 0 ? "+\(added)" : nil, removed > 0 ? "−\(removed)" : nil].compactMap { $0 }.joined(separator: " ")
    }

    static let maxLines = 40

    /// From an edit tool's old and new text (Claude Edit/MultiEdit).
    public static func edit(path: String, old: String, new: String) -> FileDiff {
        let a = split(old), b = split(new)
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var endA = a.count, endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
        var lines: [Line] = []
        if start > 0 { lines.append(Line(.context, a[start - 1])) }
        lines += a[start..<endA].map { Line(.removed, $0) }
        lines += b[start..<endB].map { Line(.added, $0) }
        if endA < a.count { lines.append(Line(.context, a[endA])) }
        return make(path: path, lines: lines, added: endB - start, removed: endA - start)
    }

    /// A whole new file (Write): every line added.
    public static func created(path: String, content: String) -> FileDiff {
        let b = split(content)
        return make(path: path, lines: b.map { Line(.added, $0) }, added: b.count, removed: 0)
    }

    /// Several edits to the same file, one after another.
    public static func merge(path: String, _ parts: [FileDiff]) -> FileDiff {
        var lines: [Line] = []
        for (i, p) in parts.enumerated() {
            if i > 0 { lines.append(Line(.gap, "…")) }
            lines += p.lines
        }
        return make(path: path, lines: lines, added: parts.reduce(0) { $0 + $1.added }, removed: parts.reduce(0) { $0 + $1.removed })
    }

    /// A unified diff (`@@`, `+`, `-` lines), as Codex reports file changes.
    public static func unified(path: String, _ text: String) -> FileDiff {
        var lines: [Line] = []
        var added = 0, removed = 0
        for raw in split(text) {
            if raw.hasPrefix("+++") || raw.hasPrefix("---") || raw.hasPrefix("diff ") || raw.hasPrefix("index ") { continue }
            if raw.hasPrefix("@@") { if !lines.isEmpty { lines.append(Line(.gap, "…")) }; continue }
            if raw.hasPrefix("+") { lines.append(Line(.added, String(raw.dropFirst()))); added += 1 }
            else if raw.hasPrefix("-") { lines.append(Line(.removed, String(raw.dropFirst()))); removed += 1 }
            else { lines.append(Line(.context, raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw)) }
        }
        return make(path: path, lines: lines, added: added, removed: removed)
    }

    private static func make(path: String, lines: [Line], added: Int, removed: Int) -> FileDiff {
        FileDiff(path: path, lines: Array(lines.prefix(maxLines)), added: added, removed: removed, truncated: lines.count > maxLines)
    }

    private static func split(_ s: String) -> [String] {
        s.isEmpty ? [] : s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }
}
