import XCTest
@testable import AxyomRemoteCore

final class OfflineCacheTests: XCTestCase {
    func tempCache() -> OfflineCache {
        OfflineCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("axyom-cache-\(UUID().uuidString)"))
    }

    func testTranscriptRoundTripKeepsNewestRows() {
        let cache = tempCache()
        cache.maxRows = 2
        let rows = (1...3).map { TranscriptItem(id: "m\($0)", sequence: $0, createdAt: Date(timeIntervalSince1970: 0), source: "x", direction: "output", hidden: false, raw: "r\($0)", text: "t\($0)") }
        cache.saveTranscript(rows, sessionId: "s1")
        XCTAssertEqual(cache.loadTranscript(sessionId: "s1").map(\.id), ["m2", "m3"])
        XCTAssertTrue(cache.loadTranscript(sessionId: "other").isEmpty)
        cache.clear()
        XCTAssertTrue(cache.loadTranscript(sessionId: "s1").isEmpty)
    }

    func testOldConversationsPruned() {
        let cache = tempCache()
        cache.maxConversations = 2
        let row = [TranscriptItem(id: "m", sequence: 1, createdAt: Date(timeIntervalSince1970: 0), source: "x", direction: "output", hidden: false, raw: "r", text: "t")]
        for id in ["a", "b", "c"] { cache.saveTranscript(row, sessionId: id); Thread.sleep(forTimeInterval: 0.02) }
        let kept = ["a", "b", "c"].filter { !cache.loadTranscript(sessionId: $0).isEmpty }
        XCTAssertEqual(kept.count, 2)
        XCTAssertTrue(kept.contains("c"))
    }

    func testClientShowsCachedSessionsBeforeConnecting() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let cache = tempCache()
        let p = try crypto.encrypt("/p"), t = try crypto.encrypt("Antes")
        cache.saveIndex([SessionIndexEntry(sessionId: "s1", encryptedProjectId: p.ciphertext, projectIdIv: p.iv, encryptedTitle: t.ciphertext, titleIv: t.iv,
                                           provider: "claude-code", lastMessageAt: 1, createdAt: 1, updatedAt: 1)])
        let pairing = PairingPayload(server: "https://sync.example", key: "k", seed: "seed", issuedAt: 0)
        let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone, factory: { _ in throw URLError(.notConnectedToInternet) })
        await client.useCache(cache)
        let snap = await client.currentSnapshot()
        XCTAssertEqual(snap.sessions.map(\.title), ["Antes"])
        XCTAssertFalse(snap.connected)
    }

    func testRemoveQueuedControl() async throws {
        let pairing = PairingPayload(server: "https://sync.example", key: "k", seed: "seed", issuedAt: 0)
        let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: try SyncCrypto(seed: "seed", memberId: "owner"), device: phone,
                                  factory: { url in box.make(url) }, sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }
        try await client.removeQueued(sessionId: "s1", promptId: "q9", targetDeviceId: "pc1")
        let frame = box.sockets[0].sent.compactMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }.last { $0["type"]?.string == "sessionControl" }
        guard case .object(let m)? = frame?["message"], case .object(let p)? = m["payload"] else { return XCTFail("no control") }
        XCTAssertEqual(m["messageType"]?.string, "remove_queued")
        XCTAssertEqual(p["promptId"]?.string, "q9")
        await client.stop()
    }
}
