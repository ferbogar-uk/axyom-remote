import XCTest
@testable import AxyomRemoteCore

final class ChatLinesTests: XCTestCase {
    private var n = 0
    private func row(_ raw: String, _ direction: String = "output") -> TranscriptItem {
        n += 1
        return TranscriptItem(id: "m\(n)", sequence: n, createdAt: Date(timeIntervalSince1970: 0), source: "x", direction: direction, hidden: false, raw: raw, text: TranscriptText.readable(raw))
    }

    /// The Cursor session from Ricardo's screenshot (2026-11-18): init, prompt,
    /// thinking deltas, assistant deltas, thinking completed, item.completed.
    func testCursorTurnBecomesTwoBubbles() {
        let items = [
            row(#"{"type":"system","subtype":"init","cwd":"C:\\AXYOM","session_id":"ac8","model":"Composer 2.5","permissionMode":"default"}"#),
            row("Teste do AXYOM: responde apenas com a palavra OK, sem usar ferramentas.", "input"),
            row(#"{"type":"thinking","subtype":"delta","text":"The"}"#),
            row(#"{"type":"thinking","subtype":"delta","text":" user"}"#),
            row(#"{"type":"thinking","subtype":"completed","session_id":"ac8","timestamp_ms":1794937112183}"#),
            row(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"OK"}]}}"#),
            row(#"{"type":"item.completed","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"OK"}]}}"#),
        ]
        let lines = ChatLines.build(items, provider: "cursor-agent")
        XCTAssertEqual(lines.map(\.text), ["Teste do AXYOM: responde apenas com a palavra OK, sem usar ferramentas.", "OK"])
        XCTAssertEqual(lines.map(\.mine), [true, false])
    }

    func testClaudeAssistantBlocksOnly() {
        let items = [
            row("Corre os testes", "input"),
            row(#"{"type":"system","subtype":"init"}"#),
            row(#"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"Vou correr."},{"type":"tool_use","name":"Bash"}]}}"#),
            row(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#, "output"),
            row(#"{"type":"result","result":"Vou correr."}"#),
            row(#"{"type":"permission_request","requestId":"r1","status":"pending"}"#),
        ]
        XCTAssertEqual(ChatLines.build(items, provider: "claude-code").map(\.text), ["Corre os testes", "Vou correr."])
    }

    func testGrokPlainTextAndDeltas() {
        let items = [
            row(#"{"type":"text","text":"O"}"#),
            row(#"{"type":"thought","text":"pensar"}"#),
            row("OK, feito."),
        ]
        XCTAssertEqual(ChatLines.build(items, provider: "grok-build").map(\.text), ["OK, feito."])
    }

    func testUnknownProviderHidesNoiseKeepsMessages() {
        let items = [
            row(#"{"type":"usage","tokens":5}"#),
            row(#"{"type":"agent_message","text":"Pronto."}"#),
            row(#"{"type":"reasoning_delta","text":"x"}"#),
        ]
        XCTAssertEqual(ChatLines.build(items, provider: "opencode").map(\.text), ["Pronto."])
    }

    func testJSONInputUsesPromptField() {
        XCTAssertEqual(ChatLines.build([row(#"{"prompt":"olá"}"#, "input")], provider: "claude-code").map(\.text), ["olá"])
    }
}
