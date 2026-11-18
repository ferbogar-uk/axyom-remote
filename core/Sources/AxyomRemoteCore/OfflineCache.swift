import Foundation

/// What the phone keeps on disk so the app opens with something to show when
/// there is no network: the last session list (still encrypted, as the server
/// sent it) and the last rows of recently opened conversations.
/// Files live in the app's own container and are excluded from iCloud backup by the app.
public final class OfflineCache: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    /// Conversations kept, newest first; older ones are deleted.
    public var maxConversations = 20
    /// Rows kept per conversation (the newest).
    public var maxRows = 400

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private func transcriptURL(_ sessionId: String) -> URL {
        let safe = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appendingPathComponent("sessions").appendingPathComponent(safe + ".json")
    }

    public func saveIndex(_ entries: [SessionIndexEntry]) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: indexURL, options: .atomic) }
    }

    public func loadIndex() -> [SessionIndexEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([SessionIndexEntry].self, from: data)) ?? []
    }

    public func saveTranscript(_ items: [TranscriptItem], sessionId: String) {
        lock.lock(); defer { lock.unlock() }
        let kept = Array(items.suffix(maxRows))
        if let data = try? JSONEncoder().encode(kept) { try? data.write(to: transcriptURL(sessionId), options: .atomic) }
        prune()
    }

    public func loadTranscript(sessionId: String) -> [TranscriptItem] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: transcriptURL(sessionId)) else { return [] }
        return (try? JSONDecoder().decode([TranscriptItem].self, from: data)) ?? []
    }

    /// Wipe everything (used when the iPhone is unpaired).
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    }

    private func prune() {
        let folder = directory.appendingPathComponent("sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in sorted.dropFirst(maxConversations) { try? FileManager.default.removeItem(at: old) }
    }
}
