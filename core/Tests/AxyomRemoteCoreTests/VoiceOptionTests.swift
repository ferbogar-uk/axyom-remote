import XCTest
@testable import AxyomRemoteCore

final class VoiceOptionTests: XCTestCase {
    func testVoiceFlagEncodesOnlyWhenSet() throws {
        let typed = try JSONEncoder().encode(PromptOptions(model: "m"))
        XCTAssertFalse(String(data: typed, encoding: .utf8)!.contains("voice"))
        let spoken = try JSONEncoder().encode(PromptOptions(voice: true))
        XCTAssertEqual(String(data: spoken, encoding: .utf8), #"{"voice":true}"#)
        XCTAssertFalse(PromptOptions(voice: true).isEmpty)
    }
}
