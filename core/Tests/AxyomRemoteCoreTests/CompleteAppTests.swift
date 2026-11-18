import XCTest
@testable import AxyomRemoteCore

final class CompleteAppTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example", key: "personal-key", seed: "seed", issuedAt: 0)
    let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)

    private var n = 0
    private func row(_ raw: String, _ direction: String = "output") -> TranscriptItem {
        n += 1
        return TranscriptItem(id: "c\(n)", sequence: n, createdAt: Date(timeIntervalSince1970: 0), source: "x", direction: direction, hidden: false, raw: raw, text: TranscriptText.readable(raw))
    }

    func started(_ crypto: SyncCrypto) async throws -> (RemoteClient, SocketBox) {
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone,
                                  factory: { url in box.make(url) },
                                  now: { Date(timeIntervalSince1970: 1_800_000_000) },
                                  sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }
        let t = try crypto.encrypt("Refactor"), p = try crypto.encrypt("/p/AXYOM")
        let e = SessionIndexEntry(sessionId: "s1", encryptedProjectId: p.ciphertext, projectIdIv: p.iv, encryptedTitle: t.ciphertext, titleIv: t.iv,
                                  provider: "claude-code", hostDeviceId: "pc1", lastMessageAt: 1000, createdAt: 1, updatedAt: 2)
        let json = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        box.sockets[0].push(#"{"type":"indexSyncResponse","sessions":[\#(json)],"projects":[]}"#)
        await assertEventually { await client.currentSnapshot().sessions.count == 1 }
        return (client, box)
    }

    func frames(_ box: SocketBox) -> [[String: JSONValue]] {
        box.sockets[0].sent.compactMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }
    }

    // MARK: Images

    func testPromptWithImageCarriesEncryptedAttachment() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let (client, box) = try await started(crypto)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01, 0x02])
        try await client.sendPrompt(sessionId: "s1", text: "", images: [PromptImage(id: "img1", filename: "foto.jpg", data: bytes, width: 640, height: 480)], targetDeviceId: nil)
        let update = try XCTUnwrap(frames(box).first { $0["type"]?.string == "indexUpdate" })
        guard case .object(let s)? = update["session"], case .array(let q)? = s["encryptedQueuedPrompts"],
              case .array(let atts)? = q.first?["encryptedAttachments"], case .object(let a)? = atts.first else { return XCTFail("no attachment") }
        XCTAssertEqual(a["filename"]?.string, "foto.jpg")
        XCTAssertEqual(a["mimeType"]?.string, "image/jpeg")
        XCTAssertEqual(a["size"]?.number, 6)
        XCTAssertEqual(a["width"]?.number, 640)
        let back = try crypto.decryptData(ciphertext: a["encryptedData"]!.string!, iv: a["iv"]!.string!)
        XCTAssertEqual(back, bytes, "the desktop decrypts the raw image bytes")
        let prompt = try crypto.decrypt(ciphertext: q.first!["encryptedPrompt"]!.string!, iv: q.first!["iv"]!.string!)
        XCTAssertEqual(prompt, "Vê a imagem em anexo.", "an image alone still sends a prompt the agent can act on")
        await client.stop()
    }

    func testMalformedAttachmentDoesNotBreakIndexEntry() throws {
        let json = #"{"sessionId":"a","encryptedProjectId":"x","projectIdIv":"y","provider":"claude-code","lastMessageAt":1,"createdAt":1,"updatedAt":1,"encryptedQueuedPrompts":[{"id":"q1","encryptedPrompt":"e","iv":"i","timestamp":5,"encryptedAttachments":[{"id":"z"}]}]}"#
        let e = try JSONDecoder().decode(SessionIndexEntry.self, from: Data(json.utf8))
        XCTAssertEqual(e.encryptedQueuedPrompts?.first?.id, "q1")
        XCTAssertNil(e.encryptedQueuedPrompts?.first?.encryptedAttachments)
    }

    // MARK: Git commit

    func testCommitProposalFoundAndAnswered() async throws {
        let req = #"{"type":"git_commit_proposal","autoApproved":false,"proposalId":"gp1","toolUseId":"tu1","filesToStage":["a.swift","b.swift"],"commitMessage":"fix: x","reasoning":"tidy","status":"pending"}"#
        let resp = #"{"type":"git_commit_proposal_response","proposalId":"gp1","action":"committed"}"#
        let pending = PendingPrompts.commits(in: [row(req)])
        XCTAssertEqual(pending.first?.id, "gp1")
        XCTAssertEqual(pending.first?.files, ["a.swift", "b.swift"])
        XCTAssertEqual(pending.first?.message, "fix: x")
        XCTAssertTrue(PendingPrompts.commits(in: [row(req), row(resp)]).isEmpty)
        let auto = req.replacingOccurrences(of: "\"autoApproved\":false", with: "\"autoApproved\":true")
        XCTAssertTrue(PendingPrompts.commits(in: [row(auto)]).isEmpty)
        XCTAssertTrue(ChatLines.build([row(req)], provider: "claude-code").isEmpty, "shown as a card, not a bubble")

        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let (client, box) = try await started(crypto)
        try await client.respondToCommit(sessionId: "s1", proposalId: "gp1", commit: true, files: ["a.swift"], message: "fix: y", targetDeviceId: "pc1")
        var control = try XCTUnwrap(frames(box).last { $0["type"]?.string == "sessionControl" })
        guard case .object(let m)? = control["message"], case .object(let p)? = m["payload"], case .object(let r)? = p["response"] else { return XCTFail() }
        XCTAssertEqual(p["promptType"]?.string, "git_commit")
        XCTAssertEqual(p["promptId"]?.string, "gp1")
        XCTAssertEqual(r["action"]?.string, "committed")
        XCTAssertEqual(r["message"]?.string, "fix: y")
        XCTAssertEqual(r["files"], .array([.string("a.swift")]))

        try await client.respondToCommit(sessionId: "s1", proposalId: "gp1", commit: false, files: [], message: "", targetDeviceId: "pc1")
        control = try XCTUnwrap(frames(box).last { $0["type"]?.string == "sessionControl" })
        guard case .object(let m2)? = control["message"], case .object(let p2)? = m2["payload"], case .object(let r2)? = p2["response"] else { return XCTFail() }
        XCTAssertEqual(r2["action"]?.string, "cancelled")
        XCTAssertNil(r2["files"])
        await client.stop()
    }

    // MARK: Plan usage

    func testPlanUsageBroadcastDecrypted() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let (client, box) = try await started(crypto)
        let plain = #"{"v":1,"desktopName":"Home Laptop","updatedAt":1763443200000,"plans":[{"id":"claude","label":"Claude","percent":31,"windows":[{"name":"5h","percent":31,"resetsAt":"2026-11-18T10:00:00Z"},{"name":"week","percent":12,"resetsAt":null}]},{"id":"codex","label":"Codex","percent":33,"windows":[]}]}"#
        let s = try crypto.encrypt(plain)
        box.sockets[0].push(#"{"type":"planUsageBroadcast","deviceId":"pc1","encryptedUsage":"\#(s.ciphertext)","usageIv":"\#(s.iv)","updatedAt":1763443200000}"#)
        await assertEventually { await !client.currentSnapshot().planUsage.isEmpty }
        let snap = await client.currentSnapshot()
        let u = try XCTUnwrap(snap.planUsage.first)
        XCTAssertEqual(u.deviceId, "pc1")
        XCTAssertEqual(u.desktopName, "Home Laptop")
        XCTAssertEqual(u.plans.map(\.label), ["Claude", "Codex"])
        XCTAssertEqual(u.plans.first?.percent, 31)
        XCTAssertNotNil(u.plans.first?.nextReset)

        // Unreadable under this key: ignored, previous value kept.
        let other = try SyncCrypto(seed: "other", memberId: "owner").encrypt(plain)
        box.sockets[0].push(#"{"type":"planUsageBroadcast","deviceId":"pc2","encryptedUsage":"\#(other.ciphertext)","usageIv":"\#(other.iv)"}"#)
        try await Task.sleep(nanoseconds: 100_000_000)
        let ids = await client.currentSnapshot().planUsage.map(\.deviceId)
        XCTAssertEqual(ids, ["pc1"])
        await client.stop()
    }

    // MARK: Routing

    func testRoutesToDesktopThatHoldsProject() {
        var a = DeviceInfo(deviceId: "office", name: "Office", type: "desktop", platform: "windows", connectedAt: 0, lastActiveAt: 0)
        a.isOnline = true; a.syncedProjectIds = ["encA"]
        var b = DeviceInfo(deviceId: "home", name: "Home", type: "desktop", platform: "windows", connectedAt: 0, lastActiveAt: 0)
        b.isOnline = true; b.syncedProjectIds = ["encB"]
        XCTAssertEqual(DesktopRouting.desktop(forEncryptedProjectId: "encB", devices: [a, b])?.deviceId, "home")
        XCTAssertEqual(DesktopRouting.desktop(forEncryptedProjectId: "unknown", devices: [a, b])?.deviceId, "office", "falls back to any online PC")
        b.isOnline = false
        XCTAssertEqual(DesktopRouting.desktop(forEncryptedProjectId: "encB", devices: [a, b])?.deviceId, "office", "an offline PC is never chosen")
        XCTAssertNil(DesktopRouting.desktop(forEncryptedProjectId: "encB", devices: []))
    }

    // MARK: Chat for other agents

    func testCodexAppServerAndExecMessages() {
        let items = [
            row(#"{"method":"item/started","params":{"item":{"type":"agentMessage","text":""}}}"#),
            row(#"{"method":"item/completed","params":{"item":{"type":"reasoning","text":"pensar"}}}"#),
            row(#"{"method":"item/completed","params":{"item":{"type":"agentMessage","text":"Feito."}}}"#),
            row(#"{"type":"item.completed","item":{"type":"agent_message","text":"Também feito."}}"#),
            row(#"{"type":"item.completed","item":{"type":"command_execution","command":"ls"}}"#),
        ]
        XCTAssertEqual(ChatLines.build(items, provider: "openai-codex").map(\.text), ["Feito.", "Também feito."])
    }

    func testGeminiPlainTextAndToolRows() {
        let items = [
            row("Olá Gemini", "input"),
            row(#"{"name":"read_file","args":{"path":"a"},"result":"..."}"#),
            row("Li o ficheiro."),
        ]
        XCTAssertEqual(ChatLines.build(items, provider: "antigravity-gemini-agent").map(\.text), ["Olá Gemini", "Li o ficheiro."])
    }

    func testSystemReminderInputHidden() {
        let items = [row("<SYSTEM_REMINDER>do X</SYSTEM_REMINDER>", "input"), row("olá", "input")]
        XCTAssertEqual(ChatLines.build(items, provider: "claude-code").map(\.text), ["olá"])
    }
}
