import Foundation

/// Reads a reply aloud while it is still being written: feed it the text so
/// far and it hands back only the sentences that are complete and not yet
/// spoken. When the final text arrives, `finish` returns whatever is left.
public struct SentenceFeeder: Equatable, Sendable {
    /// How much of the current reply has been handed out (characters).
    private(set) public var spokenCount = 0
    private var current = ""

    public init() {}

    /// Start a new reply.
    public mutating func reset() { spokenCount = 0; current = "" }

    /// New complete sentences in `text` (the whole reply so far).
    public mutating func feed(_ text: String) -> [String] {
        // The text was rewritten from the start (a different message): start over.
        if !text.hasPrefix(String(current.prefix(spokenCount))) { spokenCount = 0 }
        current = text
        let rest = Array(text.dropFirst(spokenCount))
        var out: [String] = []
        var sentence = ""
        var used = 0
        var consumed = 0
        for (i, ch) in rest.enumerated() {
            sentence.append(ch)
            let next: Character? = i + 1 < rest.count ? rest[i + 1] : nil
            // A sentence ends at . ! ? or a line break, followed by space or a new line.
            if "\n".contains(ch) || (".!?…".contains(ch) && (next == " " || next == "\n")) {
                let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                sentence = ""
                consumed = i + 1
            }
            used = i + 1
        }
        _ = used
        spokenCount += consumed
        return out
    }

    /// The reply is complete: the rest that has not been spoken.
    public mutating func finish(_ final: String) -> String? {
        var sentences = feed(final)
        let tail = String(final.dropFirst(spokenCount)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        spokenCount = final.count
        current = final
        let joined = sentences.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
