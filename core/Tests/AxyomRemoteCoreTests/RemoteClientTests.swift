import XCTest
@testable import AxyomRemoteCore

/// A scripted server end: tests push frames in and read what the client sent.
final class FakeSocket: SyncSocket, @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var inbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []
    private var closed = false
    private(set) var sent: [String] = []
    var onSend: ((String, FakeSocket) -> Void)?

    init(url: URL) { self.url = url }

    func push(_ text: String) {
        lock.lock()
        if !waiters.isEmpty { let w = waiters.removeFirst(); lock.unlock(); w.resume(returning: text); return }
        inbox.append(text); lock.unlock()
    }

    func send(_ text: String) async throws {
        lock.lock(); sent.append(text); let hook = onSend; lock.unlock()
        hook?(text, self)
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            lock.lock()
            if closed { lock.unlock(); c.resume(throwing: URLError(.networkConnectionLost)); return }
            if !inbox.isEmpty { let t = inbox.removeFirst(); lock.unlock(); c.resume(returning: t); return }
            waiters.append(c); lock.unlock()
        }
    }

    func close() {
        lock.lock(); closed = true; let ws = waiters; waiters = []; lock.unlock()
        for w in ws { w.resume(throwing: URLError(.networkConnectionLost)) }
    }

    var sentTypes: [String] {
        lock.lock(); defer { lock.unlock() }
        return sent.compactMap { (try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)))?["type"]?.string }
    }
}

final class SocketBox: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [FakeSocket] = []
    var configure: ((FakeSocket) -> Void)?
    func make(_ url: URL) -> FakeSocket {
        let s = FakeSocket(url: url)
        configure?(s)
        lock.lock(); all.append(s); lock.unlock()
        return s
    }
    var sockets: [FakeSocket] { lock.lock(); defer { lock.unlock() }; return all }
}

func eventually(_ timeout: Double = 3, _ check: @escaping () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await check() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
}

func assertEventually(_ timeout: Double = 3, file: StaticString = #filePath, line: UInt = #line, _ check: @escaping () async -> Bool) async {
    let ok = await eventually(timeout, check)
    XCTAssertTrue(ok, "condition not met in time", file: file, line: line)
}

final class RemoteClientTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example", key: "personal-key", seed: "seed", issuedAt: 0)
    let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)

    func entry(_ crypto: SyncCrypto, id: String, title: String, project: String, executing: Bool = false) throws -> String {
        let t = try crypto.encrypt(title), p = try crypto.encrypt(project)
        let e = SessionIndexEntry(sessionId: id, encryptedProjectId: p.ciphertext, projectIdIv: p.iv, encryptedTitle: t.ciphertext, titleIv: t.iv,
                                  provider: "claude-code", lastMessageAt: 1000, createdAt: 1, updatedAt: 1, isExecuting: executing)
        return String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
    }

    func makeClient(_ box: SocketBox, crypto: SyncCrypto) -> RemoteClient {
        RemoteClient(pairing: pairing, crypto: crypto, device: phone,
                     factory: { url in box.make(url) },
                     now: { Date(timeIntervalSince1970: 1_800_000_000) },
                     sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
    }

    func testConnectsAnnouncesAndListsSessions() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        let client = makeClient(box, crypto: crypto)
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }

        let index = box.sockets[0]
        XCTAssertTrue(index.url.absoluteString.hasPrefix("wss://sync.example/sync/org%3Aaxyom%3Auser%3Aowner%3Aindex?token="))
        let token = String(index.url.absoluteString.split(separator: "=").last!)
        XCTAssertEqual(PersonalJWT.secondsLeft(token, now: Date(timeIntervalSince1970: 1_800_000_000)), 300)

        index.push(#"{"type":"indexSyncResponse","sessions":[\#(try entry(crypto, id: "s1", title: "Refactor", project: "/p/AXYOM", executing: true))],"projects":[]}"#)
        index.push(#"{"type":"devicesList","devices":[{"deviceId":"pc1","name":"Home Laptop","type":"desktop","platform":"windows","connectedAt":0,"lastActiveAt":0},{"deviceId":"phone1","name":"iPhone","type":"mobile","platform":"ios","connectedAt":0,"lastActiveAt":0}]}"#)
        await assertEventually { let s = await client.currentSnapshot(); return s.connected && s.sessions.count == 1 && s.devices.count == 1 }
        let snap = await client.currentSnapshot()
        XCTAssertEqual(snap.sessions.first?.title, "Refactor")
        XCTAssertEqual(snap.devices.first?.name, "Home Laptop", "the phone does not list itself")

        index.push(#"{"type":"indexDeleteBroadcast","sessionId":"s1"}"#)
        index.push(#"{"type":"deviceLeft","deviceId":"pc1"}"#)
        await assertEventually { let s = await client.currentSnapshot(); return s.sessions.isEmpty && s.devices.isEmpty }
        await client.stop()
    }

    func testCountsRowsUnderAnotherKey() async throws {
        let mine = try SyncCrypto(seed: "seed", memberId: "owner")
        let other = try SyncCrypto(seed: "other", memberId: "owner")
        let box = SocketBox()
        let client = makeClient(box, crypto: mine)
        await client.start()
        await assertEventually { !box.sockets.isEmpty }
        box.sockets[0].push(#"{"type":"indexSyncResponse","sessions":[\#(try entry(other, id: "x", title: "t", project: "/p"))],"projects":[]}"#)
        await assertEventually { await client.currentSnapshot().unreadableRows == 1 }
        await client.stop()
    }

    func testReconnectsAfterDrop() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        let client = makeClient(box, crypto: crypto)
        await client.start()
        await assertEventually { box.sockets.count == 1 && box.sockets[0].sentTypes.count == 2 }
        box.sockets[0].close()
        await assertEventually { box.sockets.count == 2 && box.sockets[1].sentTypes.count == 2 }
        await assertEventually { await client.currentSnapshot().connected }
        await client.stop()
    }

    func testCreateSessionRoundTrip() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        // The fake "desktop" answers any createSessionRequest with success.
        box.configure = { s in
            s.onSend = { text, sock in
                guard text.contains(#""type":"createSessionRequest""#),
                      let obj = try? JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8)),
                      let rid = obj["request"]?["requestId"]?.string else { return }
                sock.push(#"{"type":"createSessionResponseBroadcast","response":{"requestId":"\#(rid)","success":true,"sessionId":"new-1"}}"#)
            }
        }
        let client = makeClient(box, crypto: crypto)
        await client.start()
        await assertEventually { await client.currentSnapshot().connected }
        let id = try await client.createSession(projectId: "/p/AXYOM", provider: "openai-codex", prompt: "review the PR", targetDeviceId: "pc1")
        XCTAssertEqual(id, "new-1")

        let sent = box.sockets[0].sent.first { $0.contains("createSessionRequest") }!
        let obj = try JSONDecoder().decode([String: JSONValue].self, from: Data(sent.utf8))
        let req = obj["request"]!
        XCTAssertEqual(obj["targetDeviceId"]?.string, "pc1")
        XCTAssertEqual(try crypto.decrypt(ciphertext: req["encryptedProjectId"]!.string!, iv: req["projectIdIv"]!.string!), "/p/AXYOM")
        XCTAssertEqual(try crypto.decrypt(ciphertext: req["encryptedInitialPrompt"]!.string!, iv: req["initialPromptIv"]!.string!), "review the PR")
        await client.stop()
    }

    func testCreateSessionTimesOut() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        let client = makeClient(box, crypto: crypto)
        await client.start()
        await assertEventually { await client.currentSnapshot().connected }
        do {
            _ = try await client.createSession(projectId: "/p", provider: nil, prompt: nil, targetDeviceId: nil, timeout: 0.01)
            XCTFail("expected timeout")
        } catch let e as RemoteClient.ClientError {
            XCTAssertEqual(e, .timeout)
        }
        await client.stop()
    }

    func testLoadsTranscriptAcrossPages() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        func row(_ n: Int, _ content: String, hidden: Bool = false) throws -> String {
            let env = #"{"content":\#(String(decoding: try JSONEncoder().encode(content), as: UTF8.self)),"metadata":null,"hidden":\#(hidden)}"#
            let s = try crypto.encrypt(env)
            return #"{"id":"m\#(n)","sequence":\#(n),"createdAt":\#(n * 1000),"source":"claude-code","direction":"output","encryptedContent":"\#(s.ciphertext)","iv":"\#(s.iv)","metadata":{}}"#
        }
        let page1 = #"{"type":"syncResponse","messages":[\#(try row(1, "plain hello")),\#(try row(2, #"{"type":"assistant","message":{"content":[{"type":"text","text":"Os testes passam."}]}}"#))],"metadata":null,"hasMore":true,"cursor":"2"}"#
        let page2 = #"{"type":"syncResponse","messages":[\#(try row(3, "internal", hidden: true))],"metadata":null,"hasMore":false,"cursor":"3"}"#
        let box = SocketBox()
        box.configure = { s in
            guard s.url.absoluteString.contains("session") else { return }
            s.onSend = { text, sock in sock.push(text.contains("sinceSeq") ? page2 : page1) }
        }
        let client = makeClient(box, crypto: crypto)
        let items = try await client.loadTranscript(sessionId: "s1")
        XCTAssertEqual(items.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(items[0].text, "plain hello")
        XCTAssertEqual(items[1].text, "Os testes passam.")
        XCTAssertTrue(items[2].hidden)
        XCTAssertTrue(box.sockets.last!.sentTypes.allSatisfy { $0 == "syncRequest" })
    }
}
