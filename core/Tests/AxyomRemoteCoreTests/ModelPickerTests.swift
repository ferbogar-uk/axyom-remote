import XCTest
@testable import AxyomRemoteCore

final class ModelPickerTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example", key: "personal-key", seed: "seed", issuedAt: 0)
    let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)

    func testUsageCarriesModelsAndDefaultEffort() throws {
        let json = #"{"v":1,"updatedAt":1,"plans":[],"defaultEffort":"high","models":[{"id":"claude-code:opus","name":"Opus 5.5","provider":"claude-code","providerLabel":"Claude","efforts":["low","medium","high","xhigh","max"]},{"id":"openai-codex:gpt-5.5","name":"GPT 5.5","provider":"openai-codex","efforts":[]},{"broken":true}]}"#
        let u = try JSONDecoder().decode(PlanUsage.self, from: Data(json.utf8))
        XCTAssertEqual(u.models.map(\.id), ["claude-code:opus", "openai-codex:gpt-5.5"], "a bad entry is skipped, not fatal")
        XCTAssertEqual(u.defaultEffort, "high")
        XCTAssertEqual(ModelPicker.choices(for: "claude-code", in: u.models).map(\.name), ["Opus 5.5"])
        XCTAssertEqual(ModelPicker.current("claude-code:opus", in: u.models)?.efforts.count, 5)
        XCTAssertEqual(ModelPicker.effortLabel("xhigh"), "xHigh")
    }

    func testIndexEffortLevelRead() throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let p = try crypto.encrypt("/p")
        var e = SessionIndexEntry(sessionId: "s", encryptedProjectId: p.ciphertext, projectIdIv: p.iv, provider: "claude-code", lastMessageAt: 1, createdAt: 1, updatedAt: 1)
        e.effortLevel = "max"
        XCTAssertEqual(FleetSession.from(e, crypto: crypto)?.effortLevel, "max")
    }

    func testPromptCarriesOptions() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone, factory: { url in box.make(url) },
                                  now: { Date(timeIntervalSince1970: 1_800_000_000) },
                                  sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }
        let p = try crypto.encrypt("/p")
        let e = SessionIndexEntry(sessionId: "s1", encryptedProjectId: p.ciphertext, projectIdIv: p.iv, provider: "claude-code", lastMessageAt: 1, createdAt: 1, updatedAt: 1)
        box.sockets[0].push(#"{"type":"indexSyncResponse","sessions":[\#(String(decoding: try JSONEncoder().encode(e), as: UTF8.self))],"projects":[]}"#)
        await assertEventually { await client.currentSnapshot().sessions.count == 1 }

        try await client.sendPrompt(sessionId: "s1", text: "olá", options: PromptOptions(model: "claude-code:opus", effortLevel: "max"), targetDeviceId: nil)
        try await client.sendPrompt(sessionId: "s1", text: "outra", options: PromptOptions(), targetDeviceId: nil)
        let updates = box.sockets[0].sent.compactMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }
            .filter { $0["type"]?.string == "indexUpdate" }
        guard updates.count == 2,
              case .object(let s1)? = updates[0]["session"], case .array(let q1)? = s1["encryptedQueuedPrompts"],
              case .object(let o)? = q1.first?["options"],
              case .object(let s2)? = updates[1]["session"], case .array(let q2)? = s2["encryptedQueuedPrompts"] else { return XCTFail("bad frames") }
        XCTAssertEqual(o["model"]?.string, "claude-code:opus")
        XCTAssertEqual(o["effortLevel"]?.string, "max")
        XCTAssertNil(o["mode"])
        XCTAssertNil(q2.first?["options"], "empty options are not sent")
        await client.stop()
    }
}
