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
    /// Last time any device read this session (shared across devices).
    public var lastReadAt: Date?
    /// Last time the session got a message.
    public var lastMessageAt: Date?
    /// Unsent text in the composer, shared between devices (client metadata).
    public var draftInput: String?
    public var draftUpdatedAt: Double?
    public var messageCount: Int?
    public var createdAt: Date?
    /// Hierarchy as on the PC: the parent session (workstream, worktree or meta-agent).
    public var parentId: String?
    public var agentRole: String?
    public var sessionType: String?
    /// Kanban phase from the PC: backlog, planning, implementing, validating, complete.
    public var phase: String?
    public var isPinned: Bool = false
    /// Set only when the session runs in a git worktree (request #9, client metadata).
    public var worktreeName: String?
    public var branch: String?
    public var worktreePath: String?

    /// Dot rule, same as the desktop: yellow = needs you (question or permission),
    /// green = still working, blue = finished with something you haven't read. No dot otherwise.
    public enum Dot: String, Codable, Equatable, Sendable { case needsYou, working, done }
    public var dot: Dot? {
        if hasPendingPrompt { return .needsYou }
        if isExecuting { return .working }
        return isUnread ? .done : nil
    }

    /// New messages since anyone last read it (and not waiting on you, which shows its own way).
    public var isUnread: Bool {
        guard let msg = lastMessageAt else { return false }
        guard let read = lastReadAt else { return true }
        return msg > read.addingTimeInterval(1)
    }

    public init(id: String, title: String, projectId: String, provider: String, model: String? = nil, isExecuting: Bool = false, hasPendingPrompt: Bool = false, queuedPromptCount: Int = 0, isArchived: Bool = false, hostDeviceId: String? = nil, lastActivity: Date, encryptedProjectId: String = "", effortLevel: String? = nil, lastReadAt: Date? = nil, lastMessageAt: Date? = nil, draftInput: String? = nil, draftUpdatedAt: Double? = nil, messageCount: Int? = nil, createdAt: Date? = nil, queued: [QueuedPreview] = []) {
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
        self.lastReadAt = lastReadAt
        self.lastMessageAt = lastMessageAt
        self.draftInput = draftInput
        self.draftUpdatedAt = draftUpdatedAt
        self.messageCount = messageCount
        self.createdAt = createdAt
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
        var draft: String?
        var draftAt: Double?
        var phase: String?
        var worktreeName: String?
        var branch: String?
        var worktreePath: String?
        if let meta = entry.encryptedClientMetadata, let iv = entry.clientMetadataIv,
           let json = try? crypto.decrypt(ciphertext: meta, iv: iv),
           let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) {
            if let flag = value["hasPendingPrompt"]?.bool { pending = flag }
            draft = value["draftInput"]?.string
            draftAt = value["draftUpdatedAt"]?.number
            phase = value["phase"]?.string
            worktreeName = value["worktreeName"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            branch = value["branch"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            worktreePath = value["worktreePath"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        }
        var s = FleetSession(
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
            lastReadAt: entry.lastReadAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            lastMessageAt: Date(timeIntervalSince1970: entry.lastMessageAt / 1000),
            draftInput: draft, draftUpdatedAt: draftAt, messageCount: entry.messageCount,
            createdAt: Date(timeIntervalSince1970: entry.createdAt / 1000),
            queued: (entry.encryptedQueuedPrompts ?? []).compactMap { q in
                (try? crypto.decrypt(ciphertext: q.encryptedPrompt, iv: q.iv)).map { QueuedPreview(id: q.id, text: $0) }
            }
        )
        s.parentId = entry.parentSessionId ?? entry.createdBySessionId
        s.agentRole = entry.agentRole
        s.sessionType = entry.sessionType
        s.phase = phase
        s.worktreeName = worktreeName
        s.branch = branch
        s.worktreePath = worktreePath
        s.isPinned = entry.isPinned ?? false
        return s
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
