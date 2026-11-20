import XCTest
@testable import AxyomRemoteCore

final class NotificationAnswerTests: XCTestCase {
    func item(_ raw: String, _ seq: Int) -> TranscriptItem {
        TranscriptItem(id: "\(seq)", sequence: seq, createdAt: Date(), source: "x", direction: "output", hidden: false, raw: raw, text: raw)
    }
    func perm(_ id: String, destructive: Bool = false) -> String {
        #"{"type":"permission_request","requestId":"\#(id)","toolName":"Edit","rawCommand":"edit a.txt","patternDisplayName":"Edit","isDestructive":\#(destructive),"warnings":[],"status":"pending"}"#
    }

    func testSinglePlainPermissionCanBeAnswered() {
        guard case .answer(let p) = NotificationAnswer.decide([item(perm("r1"), 1)], allow: true) else { return XCTFail() }
        XCTAssertEqual(p.id, "r1")
        XCTAssertEqual(NotificationAnswer.describe(p), "edit a.txt")
    }

    func testDestructiveNeedsAppToAllowButCanBeRefused() {
        let items = [item(perm("r1", destructive: true), 1)]
        XCTAssertEqual(NotificationAnswer.decide(items, allow: true), .openApp(reason: "O pedido é destrutivo: confirma na app."))
        if case .answer = NotificationAnswer.decide(items, allow: false) {} else { XCTFail() }
    }

    func testSeveralOrNoneOrOtherKinds() {
        XCTAssertEqual(NotificationAnswer.decide([item(perm("a"), 1), item(perm("b"), 2)], allow: true),
                       .openApp(reason: "Há 2 pedidos de permissão."))
        XCTAssertEqual(NotificationAnswer.decide([], allow: true), .nothingPending)
    }
}
