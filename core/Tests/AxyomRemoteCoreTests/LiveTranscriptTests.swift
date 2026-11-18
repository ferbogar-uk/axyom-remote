import XCTest
@testable import AxyomRemoteCore

final class LiveTranscriptTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example", key: "personal-key", seed: "seed", issuedAt: 0)
    let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)

    func message(_ crypto: SyncCrypto, seq: Int, text: String) throws -> String {
        let s = try crypto.encrypt(text)
        let m = EncryptedMessage(id: "m\(seq)", sequence: seq, createdAt: 1000, source: "agent", direction: "output", encryptedContent: s.ciphertext, iv: s.iv, metadata: nil)
        return String(decoding: try JSONEncoder().encode(m), as: UTF8.self)
    }

    func since(_ frame: String) -> Double? {
        (try? JSONDecoder().decode([String: JSONValue].self, from: Data(frame.utf8)))?["sinceSeq"]?.number
    }

    func testCatchesUpThenStreamsBroadcastsWithoutPolling() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone, factory: { url in box.make(url) },
                                  sleep: { _ in try? await Task.sleep(nanoseconds: 50_000_000_000) })
        let stream = client.liveTranscript(sessionId: "s1", afterSequence: 4)
        let collected = Collected()
        let reader = Task { for try await batch in stream { collected.add(batch) } }

        await assertEventually { box.sockets.first?.sentTypes == ["syncRequest"] }
        let room = box.sockets[0]
        XCTAssertTrue(room.url.absoluteString.contains("session%3As1"), room.url.absoluteString)
        XCTAssertEqual(since(room.sent[0]), 4)

        // Page 1 has more: the client asks for the next page itself.
        room.push(#"{"type":"syncResponse","messages":[\#(try message(crypto, seq: 5, text: "a"))],"hasMore":true,"cursor":"5"}"#)
        await assertEventually { room.sentTypes == ["syncRequest", "syncRequest"] }
        XCTAssertEqual(since(room.sent[1]), 5)
        room.push(#"{"type":"syncResponse","messages":[\#(try message(crypto, seq: 6, text: "b"))],"hasMore":false,"cursor":"6"}"#)
        // Then a live row arrives as a broadcast, no new request needed.
        room.push(#"{"type":"messageBroadcast","message":\#(try message(crypto, seq: 7, text: "Resposta"))}"#)
        await assertEventually { collected.texts == ["a", "b", "Resposta"] }
        XCTAssertEqual(room.sentTypes.filter { $0 == "syncRequest" }.count, 2, "no polling after catching up")

        // Socket drops: the stream ends with an error so the screen can reconnect.
        room.close()
        let result = await reader.result
        if case .success = result { XCTFail("expected the stream to fail when the socket closes") }
    }
}

final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TranscriptItem] = []
    func add(_ batch: [TranscriptItem]) { lock.lock(); items += batch; lock.unlock() }
    var texts: [String] { lock.lock(); defer { lock.unlock() }; return items.map(\.text) }
}
