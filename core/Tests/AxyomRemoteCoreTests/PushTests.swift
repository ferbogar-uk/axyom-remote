import XCTest
@testable import AxyomRemoteCore

final class PushTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example", key: "k", seed: "seed", issuedAt: 0)
    let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)

    func frames(_ s: FakeSocket) -> [[String: JSONValue]] {
        s.sent.compactMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }
    }

    func testRegisterEncoding() throws {
        let text = try ClientMessage.registerPushToken(deviceId: "phone1", token: "abcdef0123456789abcdef0123456789", development: false).encoded()
        let o = try JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
        XCTAssertEqual(o["type"]?.string, "registerPushToken")
        XCTAssertEqual(o["platform"]?.string, "ios")
        XCTAssertNil(o["environment"], "absent means production (TestFlight / App Store)")
        let dev = try ClientMessage.registerPushToken(deviceId: "p", token: "aa", development: true).encoded()
        XCTAssertTrue(dev.contains("\"environment\":\"development\""))
    }

    func testTokenSentNowAndOnEveryReconnect() async throws {
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: try SyncCrypto(seed: "seed", memberId: "owner"), device: phone,
                                  factory: { url in box.make(url) }, sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }
        await client.setPushToken("ABCDEF0123456789ABCDEF0123456789")
        let first = try XCTUnwrap(frames(box.sockets[0]).last { $0["type"]?.string == "registerPushToken" })
        XCTAssertEqual(first["token"]?.string, "abcdef0123456789abcdef0123456789")

        box.sockets[0].push(#"{"type":"registerPushTokenResult","deviceId":"phone1","ok":true,"pushConfigured":true}"#)
        await assertEventually { await client.currentSnapshot().pushReady == true }

        box.sockets[0].close()   // drop: the client reconnects and registers again
        await assertEventually { box.sockets.count >= 2 && box.sockets[1].sentTypes.contains("registerPushToken") }
        XCTAssertEqual(box.sockets[1].sentTypes.prefix(2), ["deviceAnnounce", "indexSyncRequest"])

        await client.clearPushToken()
        await assertEventually { box.sockets.last?.sentTypes.contains("unregisterPushToken") == true }
        await client.stop()
    }

    func testServerWithoutKeyReportsNotReady() async throws {
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: try SyncCrypto(seed: "seed", memberId: "owner"), device: phone,
                                  factory: { url in box.make(url) }, sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { !box.sockets.isEmpty }
        box.sockets[0].push(#"{"type":"registerPushTokenResult","deviceId":"phone1","ok":true,"pushConfigured":false}"#)
        await assertEventually { await client.currentSnapshot().pushReady == false }
        await client.stop()
    }
}
