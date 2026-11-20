import Foundation

/// Arbitrary JSON, for fields the phone passes through or only partly reads.
public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var number: Double? { if case .number(let n) = self { return n }; return nil }
}

// Mirrors of packages/runtime/src/sync/collabV3WireTypes.ts (the subset the phone uses).

public struct EncryptedMessage: Codable, Equatable, Sendable {
    public var id: String
    public var sequence: Int
    public var createdAt: Double
    public var source: String
    public var direction: String
    public var encryptedContent: String
    public var iv: String
    public var metadata: JSONValue?
}

public struct SessionIndexEntry: Codable, Equatable, Sendable {
    public var sessionId: String
    public var encryptedProjectId: String
    public var projectIdIv: String
    public var encryptedTitle: String?
    public var titleIv: String?
    public var provider: String
    public var model: String?
    public var mode: String?
    public var sessionType: String?
    public var parentSessionId: String?
    public var hostDeviceId: String?
    public var agentRole: String?
    /// Meta-agent that spawned this session (drives the PC's grouping).
    public var createdBySessionId: String?
    public var worktreeId: String?
    public var isArchived: Bool?
    public var isPinned: Bool?
    public var messageCount: Int?
    public var lastMessageAt: Double
    public var createdAt: Double
    public var updatedAt: Double
    public var isExecuting: Bool?
    public var queuedPromptCount: Int?
    public var encryptedQueuedPrompts: [EncryptedQueuedPrompt]?
    /// Plaintext effort of the session (absent = the desktop default).
    public var effortLevel: String?
    public var hasPendingPrompt: Bool?
    public var encryptedClientMetadata: String?
    public var clientMetadataIv: String?
    public var lastReadAt: Double?
}

/// A prompt waiting in a session's queue (IndexEncryptedQueuedPrompt in
/// collab-protocol). The phone sends a reply by putting one of these on the
/// session's index entry; the desktop ingests it into its queued_prompts table.
public struct EncryptedQueuedPrompt: Codable, Equatable, Sendable {
    public var id: String
    public var encryptedPrompt: String
    public var iv: String
    public var timestamp: Double
    public var source: String?
    public var encryptedAttachments: [EncryptedAttachment]?
    /// Model / effort / mode to apply right before this prompt runs (desktop request #4).
    public var options: PromptOptions?

    public init(id: String, encryptedPrompt: String, iv: String, timestamp: Double, source: String? = nil, encryptedAttachments: [EncryptedAttachment]? = nil, options: PromptOptions? = nil) {
        self.id = id
        self.encryptedPrompt = encryptedPrompt
        self.iv = iv
        self.timestamp = timestamp
        self.source = source
        self.encryptedAttachments = encryptedAttachments
        self.options = options
    }

    private enum CodingKeys: String, CodingKey { case id, encryptedPrompt, iv, timestamp, source, encryptedAttachments, options }

    /// Attachments are read leniently: a malformed one must not make the whole
    /// index entry (and with it the session list) undecodable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        encryptedPrompt = try c.decode(String.self, forKey: .encryptedPrompt)
        iv = try c.decode(String.self, forKey: .iv)
        timestamp = try c.decode(Double.self, forKey: .timestamp)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        encryptedAttachments = try? c.decodeIfPresent([EncryptedAttachment].self, forKey: .encryptedAttachments)
        options = try? c.decodeIfPresent(PromptOptions.self, forKey: .options)
    }
}

/// Per-prompt choices the desktop applies before running it.
public struct PromptOptions: Codable, Equatable, Sendable {
    public var model: String?
    public var effortLevel: String?
    public var mode: String?
    /// Sent from the voice conversation (request #12): the desktop tells the
    /// agent its reply will be read aloud. Absent = typed.
    public var voice: Bool?
    public init(model: String? = nil, effortLevel: String? = nil, mode: String? = nil, voice: Bool? = nil) {
        self.model = model; self.effortLevel = effortLevel; self.mode = mode; self.voice = voice
    }
    public var isEmpty: Bool { model == nil && effortLevel == nil && mode == nil && voice == nil }
}

/// An image sent with a prompt. `encryptedData` is the image bytes sealed with
/// AES-GCM (ciphertext||tag, base64); the desktop decrypts it in
/// `decryptMobileAttachments` (SyncManager.ts) and saves it for the agent.
public struct EncryptedAttachment: Codable, Equatable, Sendable {
    public var id: String
    public var filename: String
    public var mimeType: String
    public var encryptedData: String
    public var iv: String
    public var size: Int
    public var width: Int?
    public var height: Int?
}

public struct DeviceInfo: Codable, Equatable, Sendable {
    public var deviceId: String
    public var name: String
    public var type: String          // desktop | mobile | tablet | headless | unknown
    public var platform: String
    public var appVersion: String?
    public var connectedAt: Double
    public var lastActiveAt: Double
    public var isFocused: Bool?
    public var status: String?
    public var isOnline: Bool?
    /// Desktops on the AXYOM server list the projects they hold, as the same
    /// ciphertext as an index entry's `encryptedProjectId`. Absent = not reported.
    public var syncedProjectIds: [String]?

    public init(deviceId: String, name: String, type: String, platform: String, appVersion: String? = nil, connectedAt: Double, lastActiveAt: Double, isFocused: Bool? = nil, status: String? = nil) {
        self.deviceId = deviceId
        self.name = name
        self.type = type
        self.platform = platform
        self.appVersion = appVersion
        self.connectedAt = connectedAt
        self.lastActiveAt = lastActiveAt
        self.isFocused = isFocused
        self.status = status
    }
}

/// Ask the desktop to start a session (relayed by the server to the PC).
public struct CreateSessionRequest: Codable, Equatable, Sendable {
    public var requestId: String
    public var encryptedProjectId: String
    public var projectIdIv: String
    public var encryptedInitialPrompt: String?
    public var initialPromptIv: String?
    public var provider: String?
    public var model: String?
    public var timestamp: Double
    /// "session" | "workstream" — a manager session groups sub-agents.
    public var sessionType: String?
    /// Makes the new session a sub-agent of this one (desktop: mobileCreateRequestHandlers).
    public var parentSessionId: String?
    /// "meta-agent" for a manager, "standard" otherwise.
    public var agentRole: String?
}

public enum ServerMessage: Equatable, Sendable {
    case syncResponse(messages: [EncryptedMessage], metadata: JSONValue?, hasMore: Bool, cursor: String?)
    case messageBroadcast(EncryptedMessage)
    case metadataBroadcast(JSONValue)
    case indexSyncResponse([SessionIndexEntry])
    case indexBroadcast(SessionIndexEntry)
    case indexDeleteBroadcast(sessionId: String)
    case devicesList([DeviceInfo])
    case deviceJoined(DeviceInfo)
    case deviceLeft(deviceId: String)
    case createSessionResponse(requestId: String, success: Bool, sessionId: String?, error: String?)
    case error(code: String, message: String, requestId: String?)
    /// Reply to registerPushToken. `pushConfigured` false = the server has no APNs key yet.
    case registerPushTokenResult(deviceId: String, ok: Bool, pushConfigured: Bool)
    /// A desktop's plan usage (Claude, Codex, ...), encrypted like message content.
    case planUsageBroadcast(deviceId: String, encryptedUsage: String, usageIv: String, updatedAt: Double?)
    /// The agent's reply as it is being written (relay-only, request #11): the
    /// whole text so far, encrypted; `done` when that message is complete.
    case sessionStream(sessionId: String, encryptedText: String, iv: String, seq: Int, done: Bool)
    case pong
    /// A message type this build does not handle yet (kept so it is visible, not dropped silently).
    case unhandled(type: String)

    private struct Envelope: Decodable { let type: String }
    private struct SyncResponse: Decodable { let messages: [EncryptedMessage]; let metadata: JSONValue?; let hasMore: Bool; let cursor: String? }
    private struct MessageB: Decodable { let message: EncryptedMessage }
    private struct MetaB: Decodable { let metadata: JSONValue }
    private struct IndexSync: Decodable { let sessions: [SessionIndexEntry] }
    private struct IndexB: Decodable { let session: SessionIndexEntry }
    private struct SessionIdB: Decodable { let sessionId: String }
    private struct Devices: Decodable { let devices: [DeviceInfo] }
    private struct DeviceB: Decodable { let device: DeviceInfo }
    private struct DeviceIdB: Decodable { let deviceId: String }
    private struct CreateResp: Decodable {
        struct R: Decodable { let requestId: String; let success: Bool; let sessionId: String?; let error: String? }
        let response: R
    }
    private struct PushResult: Decodable { let deviceId: String; let ok: Bool?; let pushConfigured: Bool? }
    private struct Usage: Decodable { let deviceId: String; let encryptedUsage: String; let usageIv: String; let updatedAt: Double? }
    private struct Err: Decodable { let code: String; let message: String; let requestId: String? }

    public static func decode(_ text: String) throws -> ServerMessage {
        let data = Data(text.utf8)
        let d = JSONDecoder()
        let type = try d.decode(Envelope.self, from: data).type
        switch type {
        case "syncResponse":
            let r = try d.decode(SyncResponse.self, from: data)
            return .syncResponse(messages: r.messages, metadata: r.metadata, hasMore: r.hasMore, cursor: r.cursor)
        case "messageBroadcast": return .messageBroadcast(try d.decode(MessageB.self, from: data).message)
        case "metadataBroadcast": return .metadataBroadcast(try d.decode(MetaB.self, from: data).metadata)
        case "indexSyncResponse": return .indexSyncResponse(try d.decode(IndexSync.self, from: data).sessions)
        case "indexBroadcast": return .indexBroadcast(try d.decode(IndexB.self, from: data).session)
        case "indexDeleteBroadcast": return .indexDeleteBroadcast(sessionId: try d.decode(SessionIdB.self, from: data).sessionId)
        case "devicesList": return .devicesList(try d.decode(Devices.self, from: data).devices)
        case "deviceJoined": return .deviceJoined(try d.decode(DeviceB.self, from: data).device)
        case "deviceLeft": return .deviceLeft(deviceId: try d.decode(DeviceIdB.self, from: data).deviceId)
        case "createSessionResponseBroadcast":
            let r = try d.decode(CreateResp.self, from: data).response
            return .createSessionResponse(requestId: r.requestId, success: r.success, sessionId: r.sessionId, error: r.error)
        case "error":
            let e = try d.decode(Err.self, from: data)
            return .error(code: e.code, message: e.message, requestId: e.requestId)
        case "registerPushTokenResult", "pushTokenRegistered":
            // The server answers `pushTokenRegistered` (PROTOCOL.md); no `ok` field means it was stored.
            let r = try d.decode(PushResult.self, from: data)
            return .registerPushTokenResult(deviceId: r.deviceId, ok: r.ok ?? true, pushConfigured: r.pushConfigured ?? false)
        case "planUsageBroadcast":
            let u = try d.decode(Usage.self, from: data)
            return .planUsageBroadcast(deviceId: u.deviceId, encryptedUsage: u.encryptedUsage, usageIv: u.usageIv, updatedAt: u.updatedAt)
        case "sessionStreamBroadcast":
            struct S: Decodable { struct B: Decodable { let sessionId: String; let encryptedText: String; let iv: String; let seq: Int?; let done: Bool? }; let stream: B }
            let s = try d.decode(S.self, from: data).stream
            return .sessionStream(sessionId: s.sessionId, encryptedText: s.encryptedText, iv: s.iv, seq: s.seq ?? 0, done: s.done ?? false)
        case "pong": return .pong
        default: return .unhandled(type: type)
        }
    }
}

public enum ClientMessage: Equatable, Sendable {
    case syncRequest(sinceSeq: Int?)
    case indexSyncRequest
    case deviceAnnounce(DeviceInfo)
    case createSessionRequest(CreateSessionRequest, targetDeviceId: String?)
    /// Generic control message relayed to the PC (cancel, prompt_response, ...). The payload travels as plain JSON.
    case sessionControl(sessionId: String, messageType: String, payload: JSONValue?, sentByDeviceId: String, targetDeviceId: String?, timestamp: Double)
    /// Write (part of) a session's index entry. Omitted fields keep their stored value.
    case indexUpdate(SessionIndexEntry)
    /// Register this phone's APNs token so the server can push when the app is closed.
    case registerPushToken(deviceId: String, token: String, development: Bool)
    case unregisterPushToken(deviceId: String)
    case ping

    public func encoded() throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let object: [String: JSONValue]
        switch self {
        case .syncRequest(let since):
            object = since.map { ["type": .string("syncRequest"), "sinceSeq": .number(Double($0))] } ?? ["type": .string("syncRequest")]
        case .indexSyncRequest:
            object = ["type": .string("indexSyncRequest")]
        case .deviceAnnounce(let device):
            object = ["type": .string("deviceAnnounce"), "device": try JSONValue.from(device)]
        case .createSessionRequest(let request, let target):
            var o: [String: JSONValue] = ["type": .string("createSessionRequest"), "request": try JSONValue.from(request)]
            if let target { o["targetDeviceId"] = .string(target) }
            object = o
        case .sessionControl(let sessionId, let messageType, let payload, let sentBy, let target, let timestamp):
            var m: [String: JSONValue] = [
                "sessionId": .string(sessionId), "messageType": .string(messageType),
                "timestamp": .number(timestamp), "sentBy": .string("mobile"), "sentByDeviceId": .string(sentBy),
            ]
            if let payload { m["payload"] = payload }
            if let target { m["targetDeviceId"] = .string(target) }
            object = ["type": .string("sessionControl"), "message": .object(m)]
        case .indexUpdate(let entry):
            object = ["type": .string("indexUpdate"), "session": try JSONValue.from(entry)]
        case .registerPushToken(let deviceId, let token, let development):
            var o: [String: JSONValue] = ["type": .string("registerPushToken"), "deviceId": .string(deviceId),
                                          "token": .string(token), "platform": .string("ios")]
            if development { o["environment"] = .string("development") }
            object = o
        case .unregisterPushToken(let deviceId):
            object = ["type": .string("unregisterPushToken"), "deviceId": .string(deviceId)]
        case .ping:
            object = ["type": .string("ping")]
        }
        return String(decoding: try enc.encode(object), as: UTF8.self)
    }
}

extension JSONValue {
    static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}
