import XCTest
@testable import AxyomRemoteCore

final class EchoTests: XCTestCase {
    func row(_ id: String, _ dir: String, _ raw: String) -> TranscriptItem {
        TranscriptItem(id: id, sequence: Int(id)!, createdAt: Date(), source: "x", direction: dir, hidden: false, raw: raw, text: raw)
    }

    func testAgentEchoOfYourMessageIsDropped() {
        let items = [row("1", "input", "So what's Your Name?"),
                     row("2", "output", "So what's Your Name?"),
                     row("3", "output", "I'm Codex.")]
        XCTAssertEqual(ChatLines.build(items, provider: "openai-codex").map(\.text), ["So what's Your Name?", "I'm Codex."])
        XCTAssertEqual(ChatLines.build(items, provider: "openai-codex").map(\.mine), [true, false])
    }

    func testAgentMayRepeatYourWordsLaterInItsReply() {
        let items = [row("1", "input", "Hello."), row("2", "output", "Hi there."), row("3", "output", "Hello.")]
        XCTAssertEqual(ChatLines.build(items, provider: "openai-codex").map(\.text), ["Hello.", "Hi there.", "Hello."])
    }
}
