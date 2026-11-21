import Foundation

/// Every file the agent changed in a session, from the edit steps in the conversation:
/// one entry per file, with all its edits joined, most recently touched first.
public struct FileChange: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let diff: FileDiff
    /// How many separate edits made it up.
    public let edits: Int
    public var name: String { path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path }
    /// The folder, last two parts ("src/components").
    public var folder: String? {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return parts.count > 1 ? parts.dropLast().suffix(2).joined(separator: "/") : nil
    }
}

public enum ChangedFiles {
    public static func build(_ lines: [ChatLine]) -> [FileChange] {
        var order: [String] = []
        var parts: [String: [FileDiff]] = [:]
        for line in lines {
            guard let d = line.diff, !d.path.isEmpty else { continue }
            order.removeAll { $0 == d.path }
            order.append(d.path)
            parts[d.path, default: []].append(d)
        }
        return order.reversed().compactMap { path in
            guard let p = parts[path] else { return nil }
            return FileChange(path: path, diff: p.count == 1 ? p[0] : FileDiff.merge(path: path, p), edits: p.count)
        }
    }

    public static func totals(_ changes: [FileChange]) -> (added: Int, removed: Int) {
        (changes.reduce(0) { $0 + $1.diff.added }, changes.reduce(0) { $0 + $1.diff.removed })
    }
}
