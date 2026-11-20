import XCTest
@testable import AxyomRemoteCore

final class DotTests: XCTestCase {
    func s(exec: Bool = false, pending: Bool = false, unread: Bool = false) -> FleetSession {
        let now = Date()
        return FleetSession(id: "1", title: "t", projectId: "p", provider: "claude", isExecuting: exec, hasPendingPrompt: pending,
                            lastActivity: now, lastReadAt: unread ? now.addingTimeInterval(-60) : now, lastMessageAt: now)
    }
    func testDesktopColours() {
        XCTAssertEqual(s(exec: true, pending: true).dot, .needsYou)   // a question beats working
        XCTAssertEqual(s(exec: true, unread: true).dot, .working)
        XCTAssertEqual(s(unread: true).dot, .done)
        XCTAssertNil(s().dot)                                          // read and idle: no dot
    }
}
