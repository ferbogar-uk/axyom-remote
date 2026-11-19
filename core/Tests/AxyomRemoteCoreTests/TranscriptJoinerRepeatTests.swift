import XCTest
@testable import AxyomRemoteCore

final class TranscriptJoinerRepeatTests: XCTestCase {
    func testFinalResultAfterCommitIsNotDoubled() {
        var j = TranscriptJoiner()
        _ = j.update("Oi tudo")
        _ = j.update("Oi tudo bem")
        j.commit()
        XCTAssertEqual(j.update("Oi, tudo bem."), "Oi tudo bem")
        j.commit()
        XCTAssertEqual(j.text, "Oi tudo bem")
        XCTAssertEqual(j.update("Qual o seu nome"), "Oi tudo bem Qual o seu nome")
    }
}
