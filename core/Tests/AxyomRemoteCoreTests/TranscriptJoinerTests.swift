import XCTest
@testable import AxyomRemoteCore

final class TranscriptJoinerTests: XCTestCase {
    /// Ricardo's report (2026-11-18): after a 1-2 s pause the app wrote over what he had said.
    func testPauseKeepsEarlierPhrase() {
        var j = TranscriptJoiner()
        _ = j.update("Põe o")
        _ = j.update("Põe o Codex a rever")
        _ = j.update("Põe o Codex a rever o PR")
        // pause: iOS starts a new phrase from empty
        XCTAssertEqual(j.update("e avisa"), "Põe o Codex a rever o PR e avisa")
        XCTAssertEqual(j.update("e avisa-me quando acabar"), "Põe o Codex a rever o PR e avisa-me quando acabar")
    }

    func testGrowingPhraseIsNotDuplicated() {
        var j = TranscriptJoiner()
        _ = j.update("olá")
        _ = j.update("Olá tudo")
        XCTAssertEqual(j.update("Olá, tudo bem?"), "Olá, tudo bem?")
    }

    func testEarlyCorrectionReplacesFirstWord() {
        var j = TranscriptJoiner()
        _ = j.update("cloud")
        XCTAssertEqual(j.update("Claude abre"), "Claude abre")
    }

    func testCommitAfterTaskEndThenNewTask() {
        var j = TranscriptJoiner()
        _ = j.update("primeira frase")
        j.commit()
        XCTAssertEqual(j.update("segunda"), "primeira frase segunda")
        j.commit()
        j.commit()
        XCTAssertEqual(j.text, "primeira frase segunda")
    }

    func testEmptyUpdatesChangeNothing() {
        var j = TranscriptJoiner()
        _ = j.update("um dois três")
        XCTAssertEqual(j.update("   "), "um dois três")
        j.commit()
        XCTAssertEqual(j.text, "um dois três")
    }
}
