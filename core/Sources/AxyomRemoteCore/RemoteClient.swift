import Foundation

/// A text WebSocket. The app plugs in `URLSessionSyncSocket`; tests plug in a fake.
public protocol SyncSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// Next text frame. Throws when the socket closes.
    func receive() async throws -> String
    func close()
}

public typealias SyncSocketFactory = @Sendable (URL) async throws -> SyncSocket

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
    private var devices: [String: DeviceInfo] = [:]
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
                snapshot.lastError = "\(error)"
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
        onChange?(snapshot)
    }

    // MARK: Index room

    func handleIndex(_ msg: ServerMessage) {
        switch msg {
        case .indexSyncResponse(let entries):
            sessions = [:]
            var unreadable = 0
            for e in entries {
                if let s = FleetSession.from(e, crypto: crypto) { sessions[s.id] = s } else { unreadable += 1 }
            }
            snapshot.unreadableRows = unreadable
        case .indexBroadcast(let e):
            if let s = FleetSession.from(e, crypto: crypto) { sessions[s.id] = s }
        case .indexDeleteBroadcast(let id):
            sessions[id] = nil
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
        case .error(let code, let message, _):
            snapshot.lastError = "\(code): \(message)"
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

    private func expire(_ requestId: String) {
        pendingCreates.removeValue(forKey: requestId)?.resume(throwing: ClientError.timeout)
    }

    private func failPendingCreates(_ error: Error) {
        let all = pendingCreates
        pendingCreates = [:]
        for (_, c) in all { c.resume(throwing: error) }
    }

    /// Read a whole transcript (all pages) from the session room, then close it.
    public func loadTranscript(sessionId: String) async throws -> [TranscriptItem] {
        let room = RoomIds.session(org: pairing.org, member: pairing.member, sessionId: sessionId)
        guard let u = url(room: room) else { throw ClientError.refused("bad server address") }
        let socket = try await factory(u)
        defer { socket.close() }
        var items: [TranscriptItem] = []
        var since: Int?
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
