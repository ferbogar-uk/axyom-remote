import XCTest
@testable import AxyomRemoteCore

final class SessionInfoTests: XCTestCase {
    private var n = 0
    private func row(_ raw: String, _ direction: String = "output") -> TranscriptItem {
        n += 1
        return TranscriptItem(id: "s\(n)", sequence: n, createdAt: Date(timeIntervalSince1970: 0), source: "x", direction: direction, hidden: false, raw: raw, text: raw)
    }

    func testModelNames() {
        XCTAssertEqual(ModelInfo.display("claude-opus-4-5-20251101"), "Opus 4.5")
        XCTAssertEqual(ModelInfo.display("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(ModelInfo.display("claude-sonnet-4-20250514"), "Sonnet 4")
        XCTAssertEqual(ModelInfo.display("claude-code:opus"), "Opus")
        XCTAssertEqual(ModelInfo.display("gpt-5.5"), "GPT 5.5")
        XCTAssertEqual(ModelInfo.display("gemini-2.5-flash"), "Gemini 2.5 Flash")
        XCTAssertEqual(ModelInfo.display("Composer 2.5"), "Composer 2.5")
        XCTAssertNil(ModelInfo.display(""))
    }

    func testModelFromInitRow() {
        let items = [
            row(#"{"type":"system","subtype":"init","model":"claude-opus-4-5-20251101"}"#),
            row("olá", "input"),
            row(#"{"type":"system","subtype":"init","model":"claude-opus-5-5"}"#),
            row(#"{"type":"assistant","message":{"model":"ignored"}}"#),
        ]
        XCTAssertEqual(ModelInfo.latest(in: items), "claude-opus-5-5")
        XCTAssertNil(ModelInfo.latest(in: [row("plain")]))
    }

    func testActivityLabels() {
        XCTAssertEqual(AgentActivity.current([row(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}"#)]), "A correr um comando")
        XCTAssertEqual(AgentActivity.current([row(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}"#)]), "A ler ficheiros")
        XCTAssertEqual(AgentActivity.current([row(#"{"type":"thinking","subtype":"delta","text":"x"}"#)]), "A pensar")
        XCTAssertEqual(AgentActivity.current([row(#"{"type":"item.started","item":{"type":"command_execution","command":"ls"}}"#)]), "A correr um comando")
        XCTAssertEqual(AgentActivity.current([row("olá", "input")]), "A pensar")
        XCTAssertEqual(AgentActivity.current([]), "A trabalhar")
    }

    func testConnectionMessagesHideRawErrors() {
        XCTAssertEqual(ConnectionMessage.from(URLError(.notConnectedToInternet)), "Sem ligação à internet")
        XCTAssertEqual(ConnectionMessage.from(URLError(.timedOut)), "Sem ligação ao servidor")
        let leaky = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "wss://s/sync?token=SECRET"])
        XCTAssertFalse(ConnectionMessage.from(leaky).contains("token"))
    }

    func testQueuedPromptsDecrypted() throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let p = try crypto.encrypt("/p"), q = try crypto.encrypt("faz o passo 2")
        let e = SessionIndexEntry(sessionId: "s", encryptedProjectId: p.ciphertext, projectIdIv: p.iv, provider: "claude-code",
                                  lastMessageAt: 1, createdAt: 1, updatedAt: 1, queuedPromptCount: 1,
                                  encryptedQueuedPrompts: [EncryptedQueuedPrompt(id: "q1", encryptedPrompt: q.ciphertext, iv: q.iv, timestamp: 1)])
        XCTAssertEqual(FleetSession.from(e, crypto: crypto)?.queued, [QueuedPreview(id: "q1", text: "faz o passo 2")])
    }
}
