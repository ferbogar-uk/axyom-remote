import Foundation

/// A text WebSocket. The app plugs in `URLSessionSyncSocket`; tests plug in a fake.
public protocol SyncSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// Next text frame. Throws when the socket closes.
    func receive() async throws -> String
    func close()
}

public typealias SyncSocketFactory = @Sendable (URL) async throws -> SyncSocket

/// An image to send with a prompt (already compressed by the app, usually JPEG).
public struct PromptImage: Equatable, Sendable, Identifiable {
    public var id: String
    public var filename: String
    public var mimeType: String
    public var data: Data
    public var width: Int?
    public var height: Int?

    public init(id: String = UUID().uuidString.lowercased(), filename: String, mimeType: String = "image/jpeg", data: Data, width: Int? = nil, height: Int? = nil) {
        self.id = id; self.filename = filename; self.mimeType = mimeType; self.data = data; self.width = width; self.height = height
    }
}

/// One transcript row after decryption. `text` is a best-effort readable
/// rendering; `raw` keeps the desktop's content for richer views later.
public struct TranscriptItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var sequence: Int
    public var createdAt: Date
    public var source: String
    public var direction: String      // input = you, output = agent
    public var hidden: Bool
    public var raw: String
    public var text: String
}

/// Talks to the owner's sync server for the phone: keeps the session list and
/// the online devices current, reads transcripts, and asks the PC to start
/// sessions. Pure logic over `SyncSocket`, so it is tested on Linux.
public actor RemoteClient {
    public struct Snapshot: Equatable, Sendable {
        public var connected = false
        public var sessions: [FleetSession] = []
        public var devices: [DeviceInfo] = []
        public var lastError: String?
        /// Rows the phone could not decrypt (written under another key).
        public var unreadableRows = 0
        /// Plan usage per desktop (latest broadcast each), newest first.
        public var planUsage: [PlanUsage] = []
        public init() {}
    }

    public enum ClientError: Error, Equatable {
        case notConnected
        case timeout
        case refused(String)
    }

    private let pairing: PairingPayload
    private let crypto: SyncCrypto
    private let device: DeviceInfo
    private let factory: SyncSocketFactory
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Double) async -> Void

    private var index: SyncSocket?
    private var loop: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    private var stopped = false
    private var backoff: Double = 1
    private var sessions: [String: FleetSession] = [:]
    /// The encrypted index rows as the server sent them, so a reply can be
    /// written back without re-encrypting fields the phone cannot rebuild.
    private var entries: [String: SessionIndexEntry] = [:]
    private var devices: [String: DeviceInfo] = [:]
    private var usage: [String: PlanUsage] = [:]
    private var snapshot = Snapshot()
    private var onChange: (@Sendable (Snapshot) -> Void)?
    private var pendingCreates: [String: CheckedContinuation<String, Error>] = [:]

    public init(
        pairing: PairingPayload,
        crypto: SyncCrypto,
        device: DeviceInfo,
        factory: @escaping SyncSocketFactory,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.pairing = pairing
        self.crypto = crypto
        self.device = device
        self.factory = factory
        self.now = now
        self.sleep = sleep
    }

    public func setOnChange(_ handler: @escaping @Sendable (Snapshot) -> Void) {
        onChange = handler
        handler(snapshot)
    }

    public func currentSnapshot() -> Snapshot { snapshot }

    // MARK: Connection

    private func token() -> String {
        PersonalJWT.mint(secret: pairing.key, sub: pairing.member, org: pairing.org, now: now())
    }

    private func url(room: String) -> URL? {
        URL(string: RoomIds.url(base: pairing.webSocketBase, room: room, token: token()))
    }

    /// Open the index room and keep it open (reconnecting with backoff) until `stop()`.
    public func start() {
        stopped = false
        guard loop == nil else { return }
        loop = Task { [weak self] in await self?.runIndex() }
    }

    public func stop() {
        stopped = true
        loop?.cancel(); loop = nil
        pinger?.cancel(); pinger = nil
        index?.close(); index = nil
        setConnected(false)
    }

    private func runIndex() async {
        while !stopped && !Task.isCancelled {
            do {
                let room = RoomIds.index(org: pairing.org, member: pairing.member)
                guard let u = url(room: room) else { throw ClientError.refused("bad server address") }
                let socket = try await factory(u)
                index = socket
                try await socket.send(ClientMessage.deviceAnnounce(device).encoded())
                try await socket.send(ClientMessage.indexSyncRequest.encoded())
                setConnected(true)
                backoff = 1
                startPinging(socket)
                while !stopped {
                    let text = try await socket.receive()
                    if let msg = try? ServerMessage.decode(text) { handleIndex(msg) }
                }
            } catch {
                snapshot.lastError = ConnectionMessage.from(error)
            }
            pinger?.cancel(); pinger = nil
            index = nil
            setConnected(false)
            failPendingCreates(ClientError.notConnected)
            if stopped || Task.isCancelled { break }
            await sleep(backoff)
            backoff = min(backoff * 2, 30)
        }
    }

    private func startPinging(_ socket: SyncSocket) {
        pinger?.cancel()
        let sleep = self.sleep
        pinger = Task {
            while !Task.isCancelled {
                await sleep(30)
                if Task.isCancelled { break }
                try? await socket.send(ClientMessage.ping.encoded())
            }
        }
    }

    private func setConnected(_ value: Bool) {
        snapshot.connected = value
        if value { snapshot.lastError = nil }
        publish()
    }

    private func publish() {
        snapshot.sessions = sessions.values.sorted { $0.lastActivity > $1.lastActivity }
        snapshot.devices = devices.values.sorted { $0.name < $1.name }
        snapshot.planUsage = usage.values.sorted { $0.updatedAt > $1.updatedAt }
        onChange?(snapshot)
    }

    // MARK: Index room

    func handleIndex(_ msg: ServerMessage) {
        switch msg {
        case .indexSyncResponse(let entries):
            sessions = [:]
            self.entries = [:]
            var unreadable = 0
            for e in entries {
                if let s = FleetSession.from(e, crypto: crypto) { sessions[s.id] = s; self.entries[s.id] = e } else { unreadable += 1 }
            }
            snapshot.unreadableRows = unreadable
        case .indexBroadcast(let e):
            if let s = FleetSession.from(e, crypto: crypto) { sessions[s.id] = s; entries[s.id] = e }
        case .indexDeleteBroadcast(let id):
            sessions[id] = nil
            entries[id] = nil
        case .devicesList(let list):
            devices = Dictionary(list.filter { $0.deviceId != device.deviceId }.map { ($0.deviceId, $0) }, uniquingKeysWith: { a, _ in a })
        case .deviceJoined(let d):
            if d.deviceId != device.deviceId { devices[d.deviceId] = d }
        case .deviceLeft(let id):
            devices[id] = nil
        case .createSessionResponse(let requestId, let success, let sessionId, let error):
            if let cont = pendingCreates.removeValue(forKey: requestId) {
                if success, let sessionId { cont.resume(returning: sessionId) }
                else { cont.resume(throwing: ClientError.refused(error ?? "the desktop refused")) }
            }
            return
        case .planUsageBroadcast(let deviceId, let encrypted, let iv, _):
            guard let u = PlanUsage.decrypt(deviceId: deviceId, encryptedUsage: encrypted, usageIv: iv, crypto: crypto) else { return }
            usage[deviceId] = u
        case .error(let code, let message, _):
            snapshot.lastError = code.lowercased().contains("auth") ? "O servidor recusou este iPhone. Emparelha de novo." : "O servidor devolveu um erro"
            _ = message
        default:
            return
        }
        publish()
    }

    // MARK: Actions

    /// Ask the PC to start a session. Returns the new session id when the desktop answers.
    public func createSession(projectId: String, provider: String?, model: String? = nil, prompt: String?, targetDeviceId: String?, timeout: Double = 30) async throws -> String {
        guard let socket = index else { throw ClientError.notConnected }
        let requestId = UUID().uuidString
        let project = try crypto.encrypt(projectId)
        let sealedPrompt = try prompt.flatMap { $0.isEmpty ? nil : try crypto.encrypt($0) }
        let request = CreateSessionRequest(
            requestId: requestId,
            encryptedProjectId: project.ciphertext, projectIdIv: project.iv,
            encryptedInitialPrompt: sealedPrompt?.ciphertext, initialPromptIv: sealedPrompt?.iv,
            provider: provider, model: model,
            timestamp: now().timeIntervalSince1970 * 1000
        )
        try await socket.send(ClientMessage.createSessionRequest(request, targetDeviceId: targetDeviceId).encoded())
        let sleep = self.sleep
        let timer = Task { [weak self] in
            await sleep(timeout)
            await self?.expire(requestId)
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { pendingCreates[requestId] = $0 }
    }

    /// Answer a tool-permission prompt on the PC. `scope` is once, session, always or always-all.
    public func respondToPermission(sessionId: String, promptId: String, allow: Bool, scope: String = "once", targetDeviceId: String?) async throws {
        let payload: JSONValue = .object([
            "promptType": .string("tool_permission"),
            "promptId": .string(promptId),
            "response": .object(["decision": .string(allow ? "allow" : "deny"), "scope": .string(scope)]),
        ])
        try await sendControl(sessionId: sessionId, type: "prompt_response", payload: payload, targetDeviceId: targetDeviceId)
    }

    /// Answer an AskUserQuestion prompt. `answers` maps each question text to the chosen label(s).
    public func answerQuestion(sessionId: String, questionId: String, answers: [String: String], cancelled: Bool = false, targetDeviceId: String?) async throws {
        var response: [String: JSONValue] = ["answers": .object(answers.mapValues { .string($0) })]
        if cancelled { response["cancelled"] = .bool(true) }
        let payload: JSONValue = .object([
            "promptType": .string("ask_user_question"),
            "promptId": .string(questionId),
            "response": .object(response),
        ])
        try await sendControl(sessionId: sessionId, type: "prompt_response", payload: payload, targetDeviceId: targetDeviceId)
    }

    /// Approve or reject a plan (ExitPlanMode). Feedback travels only when rejecting.
    public func respondToPlan(sessionId: String, promptId: String, approved: Bool, feedback: String? = nil, targetDeviceId: String?) async throws {
        var response: [String: JSONValue] = ["approved": .bool(approved)]
        if !approved, let feedback, !feedback.isEmpty { response["feedback"] = .string(feedback) }
        let payload: JSONValue = .object([
            "promptType": .string("exit_plan_mode"),
            "promptId": .string(promptId),
            "response": .object(response),
        ])
        try await sendControl(sessionId: sessionId, type: "prompt_response", payload: payload, targetDeviceId: targetDeviceId)
    }

    /// Send a text reply into a session, the way the desktop's own iOS client does:
    /// an `indexUpdate` that carries one encrypted queued prompt (the desktop puts
    /// it in its queue and runs it), then a `prompt` control to nudge it to start.
    /// Returns the prompt id.
    @discardableResult
    public func sendPrompt(sessionId: String, text: String, images: [PromptImage] = [], options: PromptOptions? = nil, source: String = "keyboard", targetDeviceId: String?) async throws -> String {
        guard let socket = index else { throw ClientError.notConnected }
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !images.isEmpty { trimmed = images.count == 1 ? "Vê a imagem em anexo." : "Vê as imagens em anexo." }
        guard !trimmed.isEmpty else { throw ClientError.refused("empty prompt") }
        guard let current = entries[sessionId] else { throw ClientError.refused("unknown session") }
        let promptId = UUID().uuidString.lowercased()
        let nowMs = (now().timeIntervalSince1970 * 1000).rounded()
        let sealed = try crypto.encrypt(trimmed)
        let attachments = try images.map { img -> EncryptedAttachment in
            let s = try crypto.encryptData(img.data)
            return EncryptedAttachment(id: img.id, filename: img.filename, mimeType: img.mimeType, encryptedData: s.ciphertext,
                                       iv: s.iv, size: img.data.count, width: img.width, height: img.height)
        }
        let queued = EncryptedQueuedPrompt(id: promptId, encryptedPrompt: sealed.ciphertext, iv: sealed.iv, timestamp: nowMs, source: source,
                                           encryptedAttachments: attachments.isEmpty ? nil : attachments,
                                           options: (options?.isEmpty ?? true) ? nil : options)
        let entry = SessionIndexEntry(
            sessionId: current.sessionId,
            encryptedProjectId: current.encryptedProjectId,
            projectIdIv: current.projectIdIv,
            encryptedTitle: current.encryptedTitle,
            titleIv: current.titleIv,
            provider: current.provider,
            model: current.model,
            mode: current.mode,
            sessionType: current.sessionType,
            lastMessageAt: nowMs,
            createdAt: current.createdAt,
            updatedAt: nowMs,
            queuedPromptCount: 1,
            encryptedQueuedPrompts: [queued]
        )
        try await socket.send(ClientMessage.indexUpdate(entry).encoded())
        try await sendControl(sessionId: sessionId, type: "prompt", payload: nil, targetDeviceId: targetDeviceId ?? current.hostDeviceId)
        return promptId
    }

    /// Commit (or cancel) a git commit proposal. `files` and `message` are what the user confirmed.
    public func respondToCommit(sessionId: String, proposalId: String, commit: Bool, files: [String], message: String, targetDeviceId: String?) async throws {
        var response: [String: JSONValue] = ["action": .string(commit ? "committed" : "cancelled")]
        if commit {
            response["files"] = .array(files.map { .string($0) })
            response["message"] = .string(message)
        }
        let payload: JSONValue = .object([
            "promptType": .string("git_commit"),
            "promptId": .string(proposalId),
            "response": .object(response),
        ])
        try await sendControl(sessionId: sessionId, type: "prompt_response", payload: payload, targetDeviceId: targetDeviceId)
    }

    /// "Send now": stop the turn that is running, then nudge the PC to run the
    /// queue straight away, so the prompt you just queued runs next (the desktop
    /// does the same for its own "send now" button: stop, then drive the queue).
    public func sendNow(sessionId: String, targetDeviceId: String?) async throws {
        try await sendControl(sessionId: sessionId, type: "cancel", payload: nil, targetDeviceId: targetDeviceId)
        await sleep(0.8)
        try await sendControl(sessionId: sessionId, type: "prompt", payload: nil, targetDeviceId: targetDeviceId)
    }

    /// Archive (or bring back) a session on the PC.
    public func archive(sessionId: String, archived: Bool = true, targetDeviceId: String?) async throws {
        try await sendControl(sessionId: sessionId, type: "archive", payload: .object(["isArchived": .bool(archived)]), targetDeviceId: targetDeviceId)
    }

    /// Ask the PC to stop what the session is doing.
    public func cancel(sessionId: String, targetDeviceId: String?) async throws {
        try await sendControl(sessionId: sessionId, type: "cancel", payload: nil, targetDeviceId: targetDeviceId)
    }

    private func sendControl(sessionId: String, type: String, payload: JSONValue?, targetDeviceId: String?) async throws {
        guard let socket = index else { throw ClientError.notConnected }
        let message = ClientMessage.sessionControl(sessionId: sessionId, messageType: type, payload: payload,
                                                   sentByDeviceId: device.deviceId, targetDeviceId: targetDeviceId,
                                                   timestamp: now().timeIntervalSince1970 * 1000)
        try await socket.send(message.encoded())
    }

    private func expire(_ requestId: String) {
        pendingCreates.removeValue(forKey: requestId)?.resume(throwing: ClientError.timeout)
    }

    private func failPendingCreates(_ error: Error) {
        let all = pendingCreates
        pendingCreates = [:]
        for (_, c) in all { c.resume(throwing: error) }
    }

    /// Keep a session room open and stream its rows as they are written: first
    /// every row after `afterSequence` (paged), then each new row the server
    /// broadcasts, with no polling delay. The stream ends (throws) when the
    /// socket drops; the caller reconnects from its last sequence.
    public nonisolated func liveTranscript(sessionId: String, afterSequence: Int?) -> AsyncThrowingStream<[TranscriptItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.runLive(sessionId: sessionId, afterSequence: afterSequence, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runLive(sessionId: String, afterSequence: Int?, continuation: AsyncThrowingStream<[TranscriptItem], Error>.Continuation) async {
        let room = RoomIds.session(org: pairing.org, member: pairing.member, sessionId: sessionId)
        guard let u = url(room: room) else { continuation.finish(throwing: ClientError.refused("bad server address")); return }
        let socket: SyncSocket
        do { socket = try await factory(u) } catch { continuation.finish(throwing: error); return }
        let sleep = self.sleep
        let pinger = Task {
            while !Task.isCancelled {
                await sleep(25)
                if Task.isCancelled { break }
                try? await socket.send(ClientMessage.ping.encoded())
            }
        }
        defer { pinger.cancel(); socket.close() }
        do {
            var since = afterSequence
            var catchingUp = true
            try await socket.send(ClientMessage.syncRequest(sinceSeq: since).encoded())
            while !Task.isCancelled {
                let msg = try ServerMessage.decode(try await socket.receive())
                switch msg {
                case .syncResponse(let messages, _, let hasMore, let cursor):
                    let items = messages.compactMap { Self.decryptRow($0, crypto: crypto) }
                    if !items.isEmpty { continuation.yield(items) }
                    if catchingUp, hasMore, let c = cursor, let n = Int(c) {
                        since = n
                        try await socket.send(ClientMessage.syncRequest(sinceSeq: since).encoded())
                    } else {
                        catchingUp = false
                    }
                case .messageBroadcast(let m):
                    if let item = Self.decryptRow(m, crypto: crypto) { continuation.yield([item]) }
                case .error(let code, let message, _):
                    throw ClientError.refused("\(code): \(message)")
                default:
                    continue
                }
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Read a whole transcript (all pages) from the session room, then close it.
    public func loadTranscript(sessionId: String, afterSequence: Int? = nil) async throws -> [TranscriptItem] {
        let room = RoomIds.session(org: pairing.org, member: pairing.member, sessionId: sessionId)
        guard let u = url(room: room) else { throw ClientError.refused("bad server address") }
        let socket = try await factory(u)
        defer { socket.close() }
        var items: [TranscriptItem] = []
        var since: Int? = afterSequence
        while true {
            try await socket.send(ClientMessage.syncRequest(sinceSeq: since).encoded())
            var page: ServerMessage?
            while page == nil {
                let msg = try ServerMessage.decode(try await socket.receive())
                if case .syncResponse = msg { page = msg }
                if case .error(let code, let message, _) = msg { throw ClientError.refused("\(code): \(message)") }
            }
            guard case .syncResponse(let messages, _, let hasMore, let cursor) = page! else { break }
            items += messages.compactMap { Self.decryptRow($0, crypto: crypto) }
            guard hasMore, let c = cursor, let n = Int(c) else { break }
            since = n
        }
        return items
    }

    /// Decrypt one stored row. The desktop wraps content as {content, metadata, hidden}.
    public static func decryptRow(_ m: EncryptedMessage, crypto: SyncCrypto) -> TranscriptItem? {
        guard let plain = try? crypto.decrypt(ciphertext: m.encryptedContent, iv: m.iv) else { return nil }
        var raw = plain
        var hidden = false
        if let env = try? JSONDecoder().decode(JSONValue.self, from: Data(plain.utf8)), case .object = env {
            raw = env["content"]?.string ?? plain
            hidden = env["hidden"]?.bool ?? false
        }
        return TranscriptItem(
            id: m.id, sequence: m.sequence,
            createdAt: Date(timeIntervalSince1970: m.createdAt / 1000),
            source: m.source, direction: m.direction, hidden: hidden,
            raw: raw, text: TranscriptText.readable(raw)
        )
    }
}

/// Best-effort plain text from a provider row (often a JSON event). The full
/// rich rendering (tools, diffs) comes later; this keeps the chat readable now.
public enum TranscriptText {
    public static func readable(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return raw }
        var parts: [String] = []
        collect(value, into: &parts, depth: 0)
        let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? raw : joined
    }

    private static let textKeys: Set<String> = ["text", "prompt", "result", "message", "content"]

    private static func collect(_ v: JSONValue, into parts: inout [String], depth: Int) {
        guard depth < 8 else { return }
        switch v {
        case .string(let s) where depth > 0:
            parts.append(s)
        case .array(let a):
            for x in a { collect(x, into: &parts, depth: depth + 1) }
        case .object(let o):
            for key in o.keys.sorted() where textKeys.contains(key) {
                if let s = o[key]?.string { parts.append(s) } else if let x = o[key] { collect(x, into: &parts, depth: depth + 1) }
            }
        default:
            break
        }
    }
}
