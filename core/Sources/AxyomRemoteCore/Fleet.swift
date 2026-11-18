import Foundation

/// One AXYOM session as the home screen sees it, after decryption.
public struct FleetSession: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var projectId: String          // the desktop workspace path
    public var provider: String
    public var model: String?
    public var isExecuting: Bool
    public var hasPendingPrompt: Bool
    public var queuedPromptCount: Int
    public var isArchived: Bool
    public var hostDeviceId: String?
    public var lastActivity: Date
    /// The index entry's project ciphertext, used to find which PC holds the project.
    public var encryptedProjectId: String = ""
    /// Prompts waiting in this session's queue, decrypted (oldest first).
    public var queued: [QueuedPreview] = []
    /// The session's effort as the desktop publishes it (nil = desktop default).
    public var effortLevel: String?

    public init(id: String, title: String, projectId: String, provider: String, model: String? = nil, isExecuting: Bool = false, hasPendingPrompt: Bool = false, queuedPromptCount: Int = 0, isArchived: Bool = false, hostDeviceId: String? = nil, lastActivity: Date, encryptedProjectId: String = "", effortLevel: String? = nil, queued: [QueuedPreview] = []) {
        self.id = id
        self.title = title
        self.projectId = projectId
        self.provider = provider
        self.model = model
        self.isExecuting = isExecuting
        self.hasPendingPrompt = hasPendingPrompt
        self.queuedPromptCount = queuedPromptCount
        self.isArchived = isArchived
        self.hostDeviceId = hostDeviceId
        self.lastActivity = lastActivity
        self.encryptedProjectId = encryptedProjectId
        self.queued = queued
        self.effortLevel = effortLevel
    }

    /// Folder name of the project ("C:\…\AXYOM - AI Development OS" -> "AXYOM - AI Development OS").
    public var projectName: String { FleetBoard.projectName(projectId) }

    /// Decrypt an index entry. Returns nil when the title or project cannot be read
    /// (written under another key), so foreign rows never show as garbage.
    public static func from(_ entry: SessionIndexEntry, crypto: SyncCrypto) -> FleetSession? {
        guard let projectId = try? crypto.decrypt(ciphertext: entry.encryptedProjectId, iv: entry.projectIdIv) else { return nil }
        var title = "Untitled session"
        if let t = entry.encryptedTitle, let iv = entry.titleIv {
            guard let decrypted = try? crypto.decrypt(ciphertext: t, iv: iv) else { return nil }
            title = decrypted
        }
        var pending = entry.hasPendingPrompt ?? false
        if let meta = entry.encryptedClientMetadata, let iv = entry.clientMetadataIv,
           let json = try? crypto.decrypt(ciphertext: meta, iv: iv),
           let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)),
           let flag = value["hasPendingPrompt"]?.bool {
            pending = flag
        }
        return FleetSession(
            id: entry.sessionId,
            title: title,
            projectId: projectId,
            provider: entry.provider,
            model: entry.model,
            isExecuting: entry.isExecuting ?? false,
            hasPendingPrompt: pending,
            queuedPromptCount: entry.queuedPromptCount ?? 0,
            isArchived: entry.isArchived ?? false,
            hostDeviceId: entry.hostDeviceId,
            lastActivity: Date(timeIntervalSince1970: max(entry.lastMessageAt, entry.updatedAt) / 1000),
            encryptedProjectId: entry.encryptedProjectId,
            effortLevel: entry.effortLevel,
            queued: (entry.encryptedQueuedPrompts ?? []).compactMap { q in
                (try? crypto.decrypt(ciphertext: q.encryptedPrompt, iv: q.iv)).map { QueuedPreview(id: q.id, text: $0) }
            }
        )
    }
}

/// The "Comando" home screen: what needs you, what is running, what just happened.
public struct FleetBoard: Equatable, Sendable {
    public struct Project: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var sessionCount: Int
        public var attentionCount: Int
        /// Ciphertext of the project path, as in the index (for PC routing).
        public var encryptedId: String = ""
    }

    public var waiting: [FleetSession]
    public var working: [FleetSession]
    public var recent: [FleetSession]
    public var projects: [Project]

    public init(waiting: [FleetSession], working: [FleetSession], recent: [FleetSession], projects: [Project]) {
        self.waiting = waiting; self.working = working; self.recent = recent; self.projects = projects
    }

    /// - Parameters:
    ///   - project: only this project's sessions (nil = all). Project chips always count everything.
    public static func build(_ sessions: [FleetSession], project: String? = nil, recentLimit: Int = 10) -> FleetBoard {
        let live = sessions.filter { !$0.isArchived }
        var byProject: [String: Project] = [:]
        for s in live {
            var p = byProject[s.projectId] ?? Project(id: s.projectId, name: projectName(s.projectId), sessionCount: 0, attentionCount: 0, encryptedId: s.encryptedProjectId)
            p.sessionCount += 1
            if s.hasPendingPrompt { p.attentionCount += 1 }
            byProject[s.projectId] = p
        }
        let projects = byProject.values.sorted {
            ($0.attentionCount, $0.sessionCount, $1.name) > ($1.attentionCount, $1.sessionCount, $0.name)
        }
        let scoped = project.map { p in live.filter { $0.projectId == p } } ?? live
        let newestFirst: (FleetSession, FleetSession) -> Bool = { $0.lastActivity > $1.lastActivity }
        // A session waiting for you counts as waiting even while it runs: you are the blocker.
        let waiting = scoped.filter { $0.hasPendingPrompt }.sorted(by: newestFirst)
        let working = scoped.filter { $0.isExecuting && !$0.hasPendingPrompt }.sorted(by: newestFirst)
        let recent = scoped.filter { !$0.isExecuting && !$0.hasPendingPrompt }.sorted(by: newestFirst).prefix(recentLimit)
        return FleetBoard(waiting: waiting, working: working, recent: Array(recent), projects: projects)
    }

    public static func projectName(_ path: String) -> String {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return parts.last.map(String.init) ?? path
    }
}

/// A prompt waiting in a session's queue.
public struct QueuedPreview: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}
