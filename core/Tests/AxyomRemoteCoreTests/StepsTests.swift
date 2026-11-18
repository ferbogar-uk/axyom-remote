import XCTest
@testable import AxyomRemoteCore

final class StepsTests: XCTestCase {
    private var n = 0
    private func row(_ raw: String, _ direction: String = "output") -> TranscriptItem {
        n += 1
        return TranscriptItem(id: "t\(n)", sequence: n, createdAt: Date(timeIntervalSince1970: 0), source: "x", direction: direction, hidden: false, raw: raw, text: raw)
    }

    func testClaudeToolStepsBetweenMessages() {
        let items = [
            row("corre os testes", "input"),
            row(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Vou correr."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test\nexit"}}]}}"#),
            row(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"C:\\a\\Pairing.swift"}}]}}"#),
            row(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Passaram."}]}}"#),
        ]
        let lines = ChatLines.build(items, provider: "claude-code", includeSteps: true)
        XCTAssertEqual(lines.map(\.text), ["corre os testes", "Vou correr.", "Correu: swift test", "Leu Pairing.swift", "Passaram."])
        XCTAssertEqual(lines.map(\.isStep), [false, false, true, true, false])
        XCTAssertEqual(ChatLines.build(items, provider: "claude-code").count, 3, "steps only when asked")
    }

    func testCodexCommandAndFileChange() {
        XCTAssertEqual(Steps.describe(ChatLines.json(#"{"type":"item.completed","item":{"type":"command_execution","command":"git status"}}"#)!), ["Correu: git status"])
        XCTAssertEqual(Steps.describe(ChatLines.json(#"{"method":"item/completed","params":{"item":{"type":"fileChange","changes":[{"path":"src/a.ts"}]}}}"#)!), ["Editou a.ts"])
        XCTAssertEqual(Steps.tool("WebSearch", .object(["query": .string("swift ui")])), "Pesquisou: swift ui")
        XCTAssertEqual(Steps.tool("mcp__x__custom", nil), "Usou mcp__x__custom")
    }

    func testArchiveControl() async throws {
        let pairing = PairingPayload(server: "https://sync.example", key: "k", seed: "seed", issuedAt: 0)
        let phone = DeviceInfo(deviceId: "phone1", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)
        let box = SocketBox()
        let client = RemoteClient(pairing: pairing, crypto: try SyncCrypto(seed: "seed", memberId: "owner"), device: phone,
                                  factory: { url in box.make(url) }, sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { box.sockets.first?.sentTypes == ["deviceAnnounce", "indexSyncRequest"] }
        try await client.archive(sessionId: "s1", targetDeviceId: "pc1")
        let frame = box.sockets[0].sent.compactMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }.last { $0["type"]?.string == "sessionControl" }
        guard case .object(let m)? = frame?["message"], case .object(let p)? = m["payload"] else { return XCTFail("no control") }
        XCTAssertEqual(m["messageType"]?.string, "archive")
        XCTAssertEqual(p["isArchived"]?.bool, true)
        await client.stop()
    }
}
