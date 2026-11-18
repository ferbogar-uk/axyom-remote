import Foundation

/// Keeps everything said while the microphone is open.
///
/// iOS speech recognition reports the current phrase again and again as it
/// grows. After a pause it may start a new phrase from empty (the next partial
/// no longer continues the previous one), or end the task. Without this, the
/// screen showed only the newest phrase and a pause wiped what came before.
public struct TranscriptJoiner: Equatable, Sendable {
    private var committed: [String] = []
    private var partial = ""

    public init() {}

    /// Everything heard so far, in order.
    public var text: String {
        (committed + [partial]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Feed the recognizer's latest text for the current phrase; returns the full text.
    public mutating func update(_ latest: String) -> String {
        let new = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return text }
        if !partial.isEmpty, !new.isEmpty, Self.isRestart(previous: partial, next: new) {
            committed.append(partial)
        }
        partial = new
        return text
    }

    /// The current phrase is finished (task ended or user stopped).
    public mutating func commit() {
        if !partial.isEmpty { committed.append(partial) }
        partial = ""
    }

    /// A new phrase started if the new text does not continue the old one:
    /// it does not begin with the old phrase's first word and is not longer
    /// than it (recognizers revise words, but keep the start while growing).
    static func isRestart(previous: String, next: String) -> Bool {
        let p = TranscriptJoiner.words(previous), n = TranscriptJoiner.words(next)
        guard let firstP = p.first, let firstN = n.first else { return false }
        if firstP == firstN { return false }
        // Same length or longer with a different first word is a correction, not a restart.
        return n.count < p.count || p.count >= 3
    }

    static func words(_ s: String) -> [String] {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
