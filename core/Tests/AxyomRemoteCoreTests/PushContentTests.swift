import XCTest
@testable import AxyomRemoteCore

final class PushContentTests: XCTestCase {
    let session = FleetSession(id: "s1", title: "Análise do repositório", projectId: #"C:\Users\ricar\PROJECTS\axyom-remote"#,
                               provider: "claude-code", lastActivity: Date())

    func testFinishedNamesAgentConversationAndProject() {
        let ctx = PushContent.context(from: [session], seed: nil, member: nil)
        let t = PushContent.compose(payload: ["sessionId": "s1", "kind": "finished"], context: ctx)
        XCTAssertEqual(t.title, "Claude · Análise do repositório")
        XCTAssertEqual(t.subtitle, "Terminou · axyom-remote")
        XCTAssertEqual(t.body, "Toca para ver a resposta.")
        let w = PushContent.compose(payload: ["sessionId": "s1", "kind": "waiting"], context: ctx)
        XCTAssertEqual(w.subtitle, "À tua espera · axyom-remote")
    }

    func testUnknownSessionStillSaysWhatHappened() {
        let t = PushContent.compose(payload: ["sessionId": "zz", "kind": "error"], context: .init())
        XCTAssertEqual(t.title, "Agente")
        XCTAssertEqual(t.subtitle, "Teve um erro")
    }

    func testEncryptedTitleAndSummaryWin() throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let title = try crypto.encrypt("Corrigir login")
        let summary = try crypto.encrypt("Quer permissão para editar AuthView.swift.")
        let ctx = PushContent.context(from: [session], seed: "seed", member: "owner")
        let t = PushContent.compose(payload: ["sessionId": "s1", "kind": "waiting",
                                              "encryptedTitle": title.ciphertext, "titleIv": title.iv,
                                              "encryptedSummary": summary.ciphertext, "summaryIv": summary.iv], context: ctx)
        XCTAssertEqual(t.title, "Claude · Corrigir login")
        XCTAssertEqual(t.body, "Quer permissão para editar AuthView.swift.")
    }

    func testServerReplyNameIsAccepted() throws {
        let m = try ServerMessage.decode(#"{"type":"pushTokenRegistered","deviceId":"p","pushConfigured":true}"#)
        XCTAssertEqual(m, .registerPushTokenResult(deviceId: "p", ok: true, pushConfigured: true))
    }
}
