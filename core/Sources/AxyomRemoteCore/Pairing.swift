import Foundation

/// What the AXYOM desktop shows as a QR code to pair a phone.
///
/// Format: `axyom-pair:1:<base64url(JSON)>`. The JSON carries the server, the
/// personal key (to mint JWTs) and the encryption seed (to derive the E2E key).
/// Whoever reads the QR gets full access, so the desktop shows it only on
/// request and for a few minutes.
public struct PairingPayload: Codable, Equatable, Sendable {
    public static let prefix = "axyom-pair:1:"

    public var server: String       // https://axyom-sync.<sub>.workers.dev
    public var key: String          // personal sync key
    public var seed: String         // encryption seed
    public var org: String          // "axyom"
    public var member: String       // "owner"
    public var desktopName: String?
    public var issuedAt: Int        // unix seconds; expired codes are refused

    public init(server: String, key: String, seed: String, org: String = "axyom", member: String = "owner", desktopName: String? = nil, issuedAt: Int) {
        self.server = server
        self.key = key
        self.seed = seed
        self.org = org
        self.member = member
        self.desktopName = desktopName
        self.issuedAt = issuedAt
    }

    public enum ParseError: Error, Equatable {
        case notAxyomCode
        case unreadable
        case insecureServer
        case expired
        case missingField(String)
    }

    /// How long a shown code stays valid.
    public static let validFor: TimeInterval = 10 * 60

    public func encoded() throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return Self.prefix + PersonalJWT.base64URL(try enc.encode(self))
    }

    public static func parse(_ text: String, now: Date = Date()) throws -> PairingPayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { throw ParseError.notAxyomCode }
        guard let data = PersonalJWT.fromBase64URL(String(trimmed.dropFirst(prefix.count))),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            throw ParseError.unreadable
        }
        for (name, value) in [("server", payload.server), ("key", payload.key), ("seed", payload.seed), ("org", payload.org), ("member", payload.member)] where value.isEmpty {
            throw ParseError.missingField(name)
        }
        let isLocal = payload.server.hasPrefix("http://localhost") || payload.server.hasPrefix("http://127.0.0.1")
        guard payload.server.hasPrefix("https://") || isLocal else { throw ParseError.insecureServer }
        if now.timeIntervalSince1970 - Double(payload.issuedAt) > validFor { throw ParseError.expired }
        return payload
    }

    /// WebSocket base (`wss://…`) for room connections.
    public var webSocketBase: String {
        var base = server
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("https://") { return "wss://" + base.dropFirst("https://".count) }
        if base.hasPrefix("http://") { return "ws://" + base.dropFirst("http://".count) }
        return base
    }
}

/// Room ids the server routes on (`org:<org>:user:<member>:<suffix>`).
public enum RoomIds {
    public static func index(org: String, member: String) -> String {
        "org:\(org):user:\(member):index"
    }

    public static func session(org: String, member: String, sessionId: String) -> String {
        "org:\(org):user:\(member):session:\(sessionId)"
    }

    /// Full socket URL for a room, token in the query (browsers/iOS cannot set headers).
    public static func url(base: String, room: String, token: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let r = room.addingPercentEncoding(withAllowedCharacters: allowed) ?? room
        let t = token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
        return "\(base)/sync/\(r)?token=\(t)"
    }
}
