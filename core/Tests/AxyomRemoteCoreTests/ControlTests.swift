import XCTest
@testable import AxyomRemoteCore

final class ControlTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example", key: "personal-key", seed: "seed", issuedAt: 0)
    let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)

    func started() async throws -> (RemoteClient, SocketBox) {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone,
                                  factory: { url in box.make(url) },
                                  now: { Date(timeIntervalSince1970: 1_800_000_000) },
                                  sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }
        await assertEventually { await client.currentSnapshot().connected }
        return (client, box)
    }

    func lastControl(_ box: SocketBox) throws -> [String: JSONValue] {
        let frames = box.sockets[0].sent.compactMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }
        let control = frames.last { $0["type"]?.string == "sessionControl" }
        guard case .object(let message)? = control?["message"] else { throw XCTSkip("no sessionControl sent") }
        return message
    }

    func testSessionControlEncoding() throws {
        let text = try ClientMessage.sessionControl(sessionId: "s1", messageType: "cancel", payload: nil,
                                                    sentByDeviceId: "phone1", targetDeviceId: "pc1", timestamp: 5).encoded()
        let o = try JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
        XCTAssertEqual(o["type"]?.string, "sessionControl")
        guard case .object(let m)? = o["message"] else { return XCTFail("no message") }
        XCTAssertEqual(m["sessionId"]?.string, "s1")
        XCTAssertEqual(m["messageType"]?.string, "cancel")
        XCTAssertEqual(m["sentBy"]?.string, "mobile")
        XCTAssertEqual(m["sentByDeviceId"]?.string, "phone1")
        XCTAssertEqual(m["targetDeviceId"]?.string, "pc1")
        XCTAssertNil(m["payload"])
    }

    func testApproveSendsPromptResponse() async throws {
        let (client, box) = try await started()
        try await client.respondToPermission(sessionId: "s1", promptId: "req9", allow: true, targetDeviceId: "pc1")
        let m = try lastControl(box)
        XCTAssertEqual(m["messageType"]?.string, "prompt_response")
        XCTAssertEqual(m["targetDeviceId"]?.string, "pc1")
        guard case .object(let p)? = m["payload"], case .object(let r)? = p["response"] else { return XCTFail("bad payload") }
        XCTAssertEqual(p["promptType"]?.string, "tool_permission")
        XCTAssertEqual(p["promptId"]?.string, "req9")
        XCTAssertEqual(r["decision"]?.string, "allow")
        XCTAssertEqual(r["scope"]?.string, "once")
        await client.stop()
    }

    func testDenySendsDeny() async throws {
        let (client, box) = try await started()
        try await client.respondToPermission(sessionId: "s1", promptId: "req9", allow: false, targetDeviceId: nil)
        let m = try lastControl(box)
        guard case .object(let p)? = m["payload"], case .object(let r)? = p["response"] else { return XCTFail("bad payload") }
        XCTAssertEqual(r["decision"]?.string, "deny")
        XCTAssertNil(m["targetDeviceId"])
        await client.stop()
    }

    func testCancelSendsCancel() async throws {
        let (client, box) = try await started()
        try await client.cancel(sessionId: "s1", targetDeviceId: "pc1")
        XCTAssertEqual(try lastControl(box)["messageType"]?.string, "cancel")
        await client.stop()
    }

    func testControlFailsWhenNotConnected() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone, factory: { url in FakeSocket(url: url) })
        do {
            try await client.cancel(sessionId: "s1", targetDeviceId: nil)
            XCTFail("expected notConnected")
        } catch {
            XCTAssertEqual(error as? RemoteClient.ClientError, .notConnected)
        }
    }

    private func item(_ raw: String, _ n: Int) -> TranscriptItem {
        TranscriptItem(id: "m\(n)", sequence: n, createdAt: Date(timeIntervalSince1970: 0), source: "tool", direction: "output", hidden: false, raw: raw, text: raw)
    }

    func testPendingPermissionFoundAndCleared() {
        let request = #"{"type":"permission_request","requestId":"r1","toolName":"Bash","rawCommand":"git push","pattern":"Bash(git push:*)","patternDisplayName":"git push","isDestructive":true,"warnings":["pushes to remote"],"status":"pending"}"#
        let response = #"{"type":"permission_response","requestId":"r1","decision":"allow","scope":"once"}"#
        let pending = PendingPrompts.permissions(in: [item(request, 1)])
        XCTAssertEqual(pending.map(\.id), ["r1"])
        XCTAssertEqual(pending.first?.rawCommand, "git push")
        XCTAssertEqual(pending.first?.isDestructive, true)
        XCTAssertEqual(pending.first?.warnings, ["pushes to remote"])
        XCTAssertTrue(PendingPrompts.permissions(in: [item(request, 1), item(response, 2)]).isEmpty)
    }

    func testPendingPermissionInsideWrappedContent() {
        let inner = #"{"type":"permission_request","requestId":"r2","toolName":"Edit","rawCommand":"edit a.txt","patternDisplayName":"Edit","isDestructive":false,"warnings":[],"status":"pending"}"#
        let wrapped = "{\"content\":" + String(decoding: try! JSONEncoder().encode(inner), as: UTF8.self) + "}"
        XCTAssertEqual(PendingPrompts.permissions(in: [item(wrapped, 1)]).map(\.id), ["r2"])
    }

    func testResolvedStatusIsNotPending() {
        let request = #"{"type":"permission_request","requestId":"r3","toolName":"Bash","rawCommand":"ls","patternDisplayName":"ls","isDestructive":false,"warnings":[],"status":"resolved"}"#
        XCTAssertTrue(PendingPrompts.permissions(in: [item(request, 1)]).isEmpty)
    }
}