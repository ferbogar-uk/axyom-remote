import XCTest
import Crypto
@testable import AxyomRemoteCore

// Vectors produced by the AXYOM desktop's own WebCrypto code path
// (PBKDF2-SHA256 100k, AES-256-GCM) -- see docs/test-vectors.json.
private enum Vector {
    static let seed = "test-seed-0123456789"
    static let member = "owner"
    static let keyHex = "cef2f731f07c9d2b654c0d05cdcaa00efd75667e933fdc7702410db6770e5049"
    static let plaintext = #"{"content":"Olá AXYOM ✓","metadata":null,"hidden":false}"#
    static let iv = "AQIDBAUGBwgJCgsM"
    static let ciphertext = "eRuB5tq3p1LzD5qaWUOi9ZQWTLg0kndBg9X0xlHsJuuctIOsdMYPAZPGKJOg7osZBoAoFqGb3YZUfHG/n4zK9VrnnbA0Uv5rnO/R"
    static let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJvd25lciIsIm9yZ2FuaXphdGlvbl9pZCI6ImF4eW9tIiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjE3MDAwMDAzMDB9.cSd5oL7JFBYevQ6VXLFvoOlZKR9IMeRNr8xlzOMzkEs"
}

private func hex(_ key: SymmetricKey) -> String {
    key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
}

final class SyncCryptoTests: XCTestCase {
    func testKeyDerivationMatchesDesktop() throws {
        let key = try SyncCrypto.deriveKey(seed: Vector.seed, memberId: Vector.member)
        XCTAssertEqual(hex(key), Vector.keyHex)
    }

    func testDecryptsWhatTheDesktopEncrypted() throws {
        let crypto = try SyncCrypto(seed: Vector.seed, memberId: Vector.member)
        XCTAssertEqual(try crypto.decrypt(ciphertext: Vector.ciphertext, iv: Vector.iv), Vector.plaintext)
    }

    func testEncryptsExactlyLikeTheDesktop() throws {
        let crypto = try SyncCrypto(seed: Vector.seed, memberId: Vector.member)
        let sealed = try crypto.encrypt(Vector.plaintext, iv: Data(base64Encoded: Vector.iv)!)
        XCTAssertEqual(sealed.ciphertext, Vector.ciphertext)
        XCTAssertEqual(sealed.iv, Vector.iv)
    }

    func testRoundTripWithRandomIV() throws {
        let crypto = try SyncCrypto(seed: "another seed", memberId: "owner")
        let sealed = try crypto.encrypt("hello")
        XCTAssertEqual(try crypto.decrypt(ciphertext: sealed.ciphertext, iv: sealed.iv), "hello")
    }

    func testWrongKeyFails() throws {
        let other = try SyncCrypto(seed: "wrong seed", memberId: Vector.member)
        XCTAssertThrowsError(try other.decrypt(ciphertext: Vector.ciphertext, iv: Vector.iv))
    }
}

final class PersonalJWTTests: XCTestCase {
    func testMintMatchesDesktopAndServer() {
        let jwt = PersonalJWT.mint(secret: "unit-test-personal-key", sub: "owner", org: "axyom",
                                   now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(jwt, Vector.jwt)
    }

    func testSecondsLeft() {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        XCTAssertEqual(PersonalJWT.secondsLeft(Vector.jwt, now: now), 200)
        XCTAssertNil(PersonalJWT.secondsLeft("not.a.jwt"))
    }
}

final class PairingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func payload(server: String = "https://axyom-sync.axyom.workers.dev", issuedAt: Int = 1_800_000_000) -> PairingPayload {
        PairingPayload(server: server, key: "k", seed: "s", desktopName: "Home Laptop", issuedAt: issuedAt)
    }

    func testRoundTrip() throws {
        let code = try payload().encoded()
        XCTAssertTrue(code.hasPrefix("axyom-pair:1:"))
        XCTAssertEqual(try PairingPayload.parse(code, now: now), payload())
    }

    func testRefusesOtherCodes() {
        XCTAssertThrowsError(try PairingPayload.parse("https://example.com", now: now)) { XCTAssertEqual($0 as? PairingPayload.ParseError, .notAxyomCode) }
        XCTAssertThrowsError(try PairingPayload.parse("axyom-pair:1:%%%", now: now)) { XCTAssertEqual($0 as? PairingPayload.ParseError, .unreadable) }
    }

    func testRefusesPlainHTTPAndExpiredCodes() throws {
        XCTAssertThrowsError(try PairingPayload.parse(try payload(server: "http://evil.example").encoded(), now: now)) {
            XCTAssertEqual($0 as? PairingPayload.ParseError, .insecureServer)
        }
        XCTAssertThrowsError(try PairingPayload.parse(try payload(issuedAt: 1_800_000_000 - 11 * 60).encoded(), now: now)) {
            XCTAssertEqual($0 as? PairingPayload.ParseError, .expired)
        }
    }

    func testRoomUrls() {
        XCTAssertEqual(payload().webSocketBase, "wss://axyom-sync.axyom.workers.dev")
        XCTAssertEqual(RoomIds.index(org: "axyom", member: "owner"), "org:axyom:user:owner:index")
        XCTAssertEqual(RoomIds.url(base: "wss://h", room: "org:axyom:user:owner:index", token: "a.b.c"),
                       "wss://h/sync/org%3Aaxyom%3Auser%3Aowner%3Aindex?token=a.b.c")
    }
}

final class WireTests: XCTestCase {
    func testDecodesServerMessages() throws {
        let msg = try ServerMessage.decode(#"{"type":"syncResponse","messages":[{"id":"m1","sequence":1,"createdAt":1,"source":"assistant","direction":"output","encryptedContent":"C","iv":"I","metadata":{}}],"metadata":null,"hasMore":false,"cursor":"1"}"#)
        guard case .syncResponse(let messages, _, let hasMore, let cursor) = msg else { return XCTFail("\(msg)") }
        XCTAssertEqual(messages.first?.id, "m1"); XCTAssertFalse(hasMore); XCTAssertEqual(cursor, "1")

        XCTAssertEqual(try ServerMessage.decode(#"{"type":"deviceLeft","deviceId":"d1"}"#), .deviceLeft(deviceId: "d1"))
        XCTAssertEqual(try ServerMessage.decode(#"{"type":"pong"}"#), .pong)
        XCTAssertEqual(try ServerMessage.decode(#"{"type":"error","code":"unknown_message_type","message":"x","requestId":"r"}"#),
                       .error(code: "unknown_message_type", message: "x", requestId: "r"))
        XCTAssertEqual(try ServerMessage.decode(#"{"type":"somethingNew"}"#), .unhandled(type: "somethingNew"))
    }

    func testEncodesClientMessages() throws {
        XCTAssertEqual(try ClientMessage.indexSyncRequest.encoded(), #"{"type":"indexSyncRequest"}"#)
        XCTAssertEqual(try ClientMessage.syncRequest(sinceSeq: 200).encoded(), #"{"sinceSeq":200,"type":"syncRequest"}"#)
        let req = CreateSessionRequest(requestId: "r1", encryptedProjectId: "E", projectIdIv: "I", provider: "claude-code", timestamp: 1)
        let text = try ClientMessage.createSessionRequest(req, targetDeviceId: "pc").encoded()
        XCTAssertTrue(text.contains(#""targetDeviceId":"pc""#))
        XCTAssertTrue(text.contains(#""type":"createSessionRequest""#))
    }
}

final class FleetTests: XCTestCase {
    func s(_ id: String, project: String = "C:\\P\\AXYOM", executing: Bool = false, pending: Bool = false, archived: Bool = false, at: Double) -> FleetSession {
        FleetSession(id: id, title: id, projectId: project, provider: "claude-code", isExecuting: executing, hasPendingPrompt: pending, isArchived: archived, lastActivity: Date(timeIntervalSince1970: at))
    }

    func testGroupsWaitingWorkingRecent() {
        let board = FleetBoard.build([
            s("a", executing: true, at: 3),
            s("b", executing: true, pending: true, at: 2),   // waiting wins over working
            s("c", at: 5),
            s("d", archived: true, at: 9),
            s("e", project: "/home/r/Hefesto", pending: true, at: 1),
        ])
        XCTAssertEqual(board.waiting.map(\.id), ["b", "e"])
        XCTAssertEqual(board.working.map(\.id), ["a"])
        XCTAssertEqual(board.recent.map(\.id), ["c"])
        XCTAssertEqual(board.projects.map(\.name), ["AXYOM", "Hefesto"])
        XCTAssertEqual(board.projects.first?.attentionCount, 1)
    }

    func testProjectFilterKeepsAllProjectChips() {
        let board = FleetBoard.build([s("a", at: 1), s("e", project: "/x/Hefesto", pending: true, at: 2)], project: "/x/Hefesto")
        XCTAssertEqual(board.waiting.map(\.id), ["e"])
        XCTAssertTrue(board.recent.isEmpty)
        XCTAssertEqual(board.projects.count, 2)
    }

    func testDecryptsIndexEntry() throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let title = try crypto.encrypt("Refactor do sync")
        let project = try crypto.encrypt("C:\\Users\\r\\PROJECTS\\AXYOM - AI Development OS")
        let meta = try crypto.encrypt(#"{"hasPendingPrompt":true}"#)
        let entry = SessionIndexEntry(sessionId: "s1", encryptedProjectId: project.ciphertext, projectIdIv: project.iv,
                                      encryptedTitle: title.ciphertext, titleIv: title.iv, provider: "claude-code",
                                      lastMessageAt: 2_000, createdAt: 1_000, updatedAt: 1_500,
                                      isExecuting: true, encryptedClientMetadata: meta.ciphertext, clientMetadataIv: meta.iv)
        let session = try XCTUnwrap(FleetSession.from(entry, crypto: crypto))
        XCTAssertEqual(session.title, "Refactor do sync")
        XCTAssertEqual(session.projectName, "AXYOM - AI Development OS")
        XCTAssertTrue(session.hasPendingPrompt)
        XCTAssertEqual(session.lastActivity, Date(timeIntervalSince1970: 2))

        let stranger = try SyncCrypto(seed: "other", memberId: "owner")
        XCTAssertNil(FleetSession.from(entry, crypto: stranger), "rows under another key are hidden, not shown as garbage")
    }
}

final class VoiceTests: XCTestCase {
    let parser = VoiceCommandParser(knownProjects: ["AXYOM - AI Development OS", "Hefesto", "Ferbogar"])

    func testNewSessionWithAgentAndProject() {
        XCTAssertEqual(parser.parse("Põe o Codex a rever o PR do sync no AXYOM"),
                       .newSession(agent: .codex, project: "AXYOM - AI Development OS", prompt: "Põe o Codex a rever o PR do sync no AXYOM"))
        XCTAssertEqual(parser.parse("ask Claude to fix the tests in hefesto"),
                       .newSession(agent: .claude, project: "Hefesto", prompt: "ask Claude to fix the tests in hefesto"))
    }

    func testCommonMishearing() {
        guard case .newSession(let agent, _, _) = parser.parse("pede ao cloud para resumir o dia") else { return XCTFail() }
        XCTAssertEqual(agent, .claude)
    }

    func testApproveDenyStatus() {
        XCTAssertEqual(parser.parse("Aprova"), .approve)
        XCTAssertEqual(parser.parse("não aprova"), .deny)
        XCTAssertEqual(parser.parse("o que está a acontecer?"), .status)
    }

    func testReplyAndEmpty() {
        XCTAssertEqual(parser.parse("usa a opção dois"), .reply(prompt: "usa a opção dois"))
        XCTAssertEqual(parser.parse("   "), .empty)
    }

    func testProviderIds() {
        XCTAssertEqual(VoiceAgent.grok.providerId, "grok-build")
        XCTAssertEqual(VoiceAgent.claude.providerId, "claude-code")
    }
}
