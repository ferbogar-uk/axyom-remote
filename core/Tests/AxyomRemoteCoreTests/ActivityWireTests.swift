import XCTest
@testable import AxyomRemoteCore

final class ActivityWireTests: XCTestCase {
    func testRegisterAndEndEncode() throws {
        let r = try ClientMessage.registerActivityToken(sessionId: "s1", token: "ab", deviceId: "d1", development: true).encoded()
        XCTAssertEqual(r, #"{"deviceId":"d1","environment":"development","sessionId":"s1","token":"ab","type":"registerActivityToken"}"#)
        let e = try ClientMessage.endActivityToken(sessionId: "s1", deviceId: "d1").encoded()
        XCTAssertEqual(e, #"{"deviceId":"d1","sessionId":"s1","type":"endActivityToken"}"#)
    }

    func testReplyDecodes() throws {
        let m = try ServerMessage.decode(#"{"type":"activityTokenRegistered","sessionId":"s1","deviceId":"d1","phase":"working","pushConfigured":true}"#)
        XCTAssertEqual(m, .activityTokenRegistered(sessionId: "s1", phase: "working", pushConfigured: true))
    }
}
