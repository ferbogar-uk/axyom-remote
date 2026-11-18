import XCTest
@testable import AxyomRemoteCore

final class ReplyTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example", key: "personal-key", seed: "seed", issuedAt: 0)
    let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)

    func entryJSON(_ crypto: SyncCrypto, id: String, host: String? = "pc1") throws -> String {
        let t = try crypto.encrypt("Refactor"), p = try crypto.encrypt("/p/AXYOM")
        let e = SessionIndexEntry(sessionId: id, encryptedProjectId: p.ciphertext, projectIdIv: p.iv, encryptedTitle: t.ciphertext, titleIv: t.iv,
                                  provider: "claude-code", model: "claude-code:opus", mode: "agent", hostDeviceId: host,
                                  messageCount: 9, lastMessageAt: 1000, createdAt: 1, updatedAt: 2, isExecuting: true)
        return String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
    }

    func started(_ crypto: SyncCrypto) async throws -> (RemoteClient, SocketBox) {
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone,
                                  factory: { url in box.make(url) },
                                  now: { Date(timeIntervalSince1970: 1_800_000_000) },
                                  sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }
        box.sockets[0].push(#"{"type":"indexSyncResponse","sessions":[\#(try entryJSON(crypto, id: "s1"))],"projects":[]}"#)
        await assertEventually { await client.currentSnapshot().sessions.count == 1 }
        return (client, box)
    }

    func frames(_ box: SocketBox) -> [[String: JSONValue]] {
        box.sockets[0].sent.compactMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }
    }

    func testSendPromptWritesEncryptedQueuedPromptThenNudges() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let (client, box) = try await started(crypto)
        let id = try await client.sendPrompt(sessionId: "s1", text: "  continua com o passo 2  ", targetDeviceId: nil)

        let sent = frames(box).filter { $0["type"]?.string != "ping" }
        let update = try XCTUnwrap(sent.first { $0["type"]?.string == "indexUpdate" })
        guard case .object(let s)? = update["session"] else { return XCTFail("no session") }
        XCTAssertEqual(s["sessionId"]?.string, "s1")
        XCTAssertEqual(s["provider"]?.string, "claude-code")
        XCTAssertEqual(s["queuedPromptCount"]?.number, 1)
        XCTAssertNil(s["isExecuting"], "execution state belongs to the desktop")
        XCTAssertNil(s["messageCount"], "omitted keeps the server's count")
        XCTAssertNil(s["hostDeviceId"])
        XCTAssertNotNil(s["encryptedProjectId"]?.string)
        guard case .array(let queue)? = s["encryptedQueuedPrompts"], case .object(let q)? = queue.first else { return XCTFail("no queue") }
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(q["id"]?.string, id)
        XCTAssertFalse(id.hasPrefix("local-"), "the desktop skips local- ids from other devices")
        XCTAssertEqual(q["source"]?.string, "keyboard")
        let plain = try crypto.decrypt(ciphertext: q["encryptedPrompt"]!.string!, iv: q["iv"]!.string!)
        XCTAssertEqual(plain, "continua com o passo 2")

        // The nudge comes after the write and goes to the session's host desktop.
        let updateIndex = sent.firstIndex { $0["type"]?.string == "indexUpdate" }!
        let controlIndex = try XCTUnwrap(sent.lastIndex { $0["type"]?.string == "sessionControl" })
        XCTAssertGreaterThan(controlIndex, updateIndex)
        guard case .object(let m)? = sent[controlIndex]["message"] else { return XCTFail("no control") }
        XCTAssertEqual(m["messageType"]?.string, "prompt")
        XCTAssertEqual(m["targetDeviceId"]?.string, "pc1")
        await client.stop()
    }

    func testSendPromptRejectsEmptyAndUnknown() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let (client, _) = try await started(crypto)
        do { try await client.sendPrompt(sessionId: "s1", text: "   ", targetDeviceId: nil); XCTFail("empty sent") } catch {}
        do { try await client.sendPrompt(sessionId: "nope", text: "olá", targetDeviceId: nil); XCTFail("unknown sent") } catch {}
        await client.stop()
    }

    func testQueuedPromptsDecodeFromIndex() throws {
        let json = #"{"sessionId":"a","encryptedProjectId":"x","projectIdIv":"y","provider":"claude-code","lastMessageAt":1,"createdAt":1,"updatedAt":1,"queuedPromptCount":1,"encryptedQueuedPrompts":[{"id":"q1","encryptedPrompt":"e","iv":"i","timestamp":5,"options":{"mode":"planning"},"encryptedAttachments":[{"id":"z"}]}]}"#
        let e = try JSONDecoder().decode(SessionIndexEntry.self, from: Data(json.utf8))
        XCTAssertEqual(e.encryptedQueuedPrompts?.first?.id, "q1")
    }

    func testAnswerQuestionPayload() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let (client, box) = try await started(crypto)
        try await client.answerQuestion(sessionId: "s1", questionId: "q7", answers: ["Qual base de dados?": "Postgres"], targetDeviceId: "pc1")
        let control = try XCTUnwrap(frames(box).last { $0["type"]?.string == "sessionControl" })
        guard case .object(let m)? = control["message"], case .object(let p)? = m["payload"],
              case .object(let r)? = p["response"], case .object(let a)? = r["answers"] else { return XCTFail("bad payload") }
        XCTAssertEqual(m["messageType"]?.string, "prompt_response")
        XCTAssertEqual(p["promptType"]?.string, "ask_user_question")
        XCTAssertEqual(p["promptId"]?.string, "q7")
        XCTAssertEqual(a["Qual base de dados?"]?.string, "Postgres")
        XCTAssertNil(r["cancelled"])
        await client.stop()
    }

    func testPlanApproveAndRejectPayloads() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let (client, box) = try await started(crypto)
        try await client.respondToPlan(sessionId: "s1", promptId: "p1", approved: true, feedback: "ignored", targetDeviceId: nil)
        var control = try XCTUnwrap(frames(box).last { $0["type"]?.string == "sessionControl" })
        guard case .object(let m1)? = control["message"], case .object(let p1)? = m1["payload"], case .object(let r1)? = p1["response"] else { return XCTFail() }
        XCTAssertEqual(p1["promptType"]?.string, "exit_plan_mode")
        XCTAssertEqual(r1["approved"]?.bool, true)
        XCTAssertNil(r1["feedback"])

        try await client.respondToPlan(sessionId: "s1", promptId: "p1", approved: false, feedback: "falta testes", targetDeviceId: nil)
        control = try XCTUnwrap(frames(box).last { $0["type"]?.string == "sessionControl" })
        guard case .object(let m2)? = control["message"], case .object(let p2)? = m2["payload"], case .object(let r2)? = p2["response"] else { return XCTFail() }
        XCTAssertEqual(r2["approved"]?.bool, false)
        XCTAssertEqual(r2["feedback"]?.string, "falta testes")
        await client.stop()
    }

    private func item(_ raw: String, _ n: Int, direction: String = "output", hidden: Bool = false) -> TranscriptItem {
        TranscriptItem(id: "m\(n)", sequence: n, createdAt: Date(timeIntervalSince1970: 0), source: "assistant", direction: direction, hidden: hidden, raw: raw, text: TranscriptText.readable(raw))
    }

    func testPendingQuestionParsedAndCleared() {
        let req = #"{"type":"ask_user_question_request","questionId":"q1","questions":[{"question":"Qual base de dados?","header":"BD","options":[{"label":"Postgres","description":"relacional"},{"label":"SQLite","description":"ficheiro"}],"multiSelect":false}],"timestamp":1,"status":"pending"}"#
        let resp = #"{"type":"ask_user_question_response","questionId":"q1","answers":{"Qual base de dados?":"Postgres"}}"#
        let pending = PendingPrompts.questions(in: [item(req, 1)])
        XCTAssertEqual(pending.first?.id, "q1")
        XCTAssertEqual(pending.first?.questions.first?.options.map(\.label), ["Postgres", "SQLite"])
        XCTAssertEqual(pending.first?.questions.first?.header, "BD")
        XCTAssertTrue(PendingPrompts.questions(in: [item(req, 1), item(resp, 2)]).isEmpty)
    }

    func testPendingPlanParsedAndCleared() {
        let req = #"{"type":"exit_plan_mode_request","requestId":"p1","planSummary":"1. Criar tabela","planFilePath":"plans/x.md","timestamp":1,"status":"pending"}"#
        let resp = #"{"type":"exit_plan_mode_response","requestId":"p1","approved":true}"#
        XCTAssertEqual(PendingPrompts.plans(in: [item(req, 1)]).first?.summary, "1. Criar tabela")
        XCTAssertTrue(PendingPrompts.plans(in: [item(req, 1), item(resp, 2)]).isEmpty)
        let done = req.replacingOccurrences(of: "\"pending\"", with: "\"resolved\"")
        XCTAssertTrue(PendingPrompts.plans(in: [item(done, 1)]).isEmpty)
    }

    func testAttentionWatcherFiresOncePerWait() {
        func s(_ id: String, _ pending: Bool) -> FleetSession {
            FleetSession(id: id, title: id, projectId: "/p", provider: "claude-code", hasPendingPrompt: pending, lastActivity: Date(timeIntervalSince1970: 0))
        }
        var w = AttentionWatcher()
        XCTAssertTrue(w.update([s("a", true)]).isEmpty, "first call only learns")
        XCTAssertEqual(w.update([s("a", true), s("b", true)]).map(\.id), ["b"])
        XCTAssertTrue(w.update([s("a", true), s("b", true)]).isEmpty)
        XCTAssertTrue(w.update([s("a", false), s("b", true)]).isEmpty)
        XCTAssertEqual(w.update([s("a", true), s("b", true)]).map(\.id), ["a"])
    }

    func testSpokenReplySkipsInputAndJSON() {
        let lines = SpokenReply.lines(from: [
            item("olá", 1, direction: "input"),
            item("Feito, o teste passou.", 2),
            item("segredo", 3, hidden: true),
            item(String(repeating: "a", count: 700), 4),
        ], maxCharacters: 600)
        XCTAssertEqual(lines.first, "Feito, o teste passou.")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.last?.count, 601)
    }

    func testFinishWatcherFiresWhenWorkStops() {
        func s(_ id: String, working: Bool, waiting: Bool = false) -> FleetSession {
            FleetSession(id: id, title: id, projectId: "/p", provider: "claude-code", isExecuting: working, hasPendingPrompt: waiting, lastActivity: Date(timeIntervalSince1970: 0))
        }
        var w = FinishWatcher()
        XCTAssertTrue(w.update([s("a", working: true)]).isEmpty, "first call only learns")
        XCTAssertTrue(w.update([s("a", working: true)]).isEmpty)
        XCTAssertEqual(w.update([s("a", working: false)]).map(\.id), ["a"])
        XCTAssertTrue(w.update([s("a", working: false)]).isEmpty)
        _ = w.update([s("b", working: true)])
        XCTAssertTrue(w.update([s("b", working: false, waiting: true)]).isEmpty, "waiting for you is the other notice")
    }
}
