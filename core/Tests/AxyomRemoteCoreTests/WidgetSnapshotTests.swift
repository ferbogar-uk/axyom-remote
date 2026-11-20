import XCTest
@testable import AxyomRemoteCore

final class WidgetSnapshotTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func s(_ id: String, exec: Bool = false, pending: Bool = false, unread: Bool = false, ago: Double = 0, archived: Bool = false) -> FleetSession {
        let t = now.addingTimeInterval(-ago)
        return FleetSession(id: id, title: "S\(id)", projectId: "p", provider: "claude", isExecuting: exec, hasPendingPrompt: pending,
                            isArchived: archived, lastActivity: t, lastReadAt: unread ? t.addingTimeInterval(-60) : t, lastMessageAt: t)
    }

    func testOrderCountsAndArchivedLeftOut() {
        let snap = WidgetSnapshot.make(sessions: [s("idle"), s("done", unread: true), s("work", exec: true, ago: 50),
                                                  s("ask", pending: true, ago: 99), s("old", pending: true, archived: true)],
                                       usage: [], pc: .online(name: "Home Laptop"), now: now)
        XCTAssertEqual(snap.items.map(\.id), ["ask", "work", "done", "idle"])
        XCTAssertEqual(snap.waitingCount, 1)
        XCTAssertEqual(snap.workingCount, 1)
        XCTAssertTrue(snap.pcOnline)
        XCTAssertEqual(snap.pcName, "Home Laptop")
    }

    func testSameContentIgnoresTime() {
        let a = WidgetSnapshot.make(sessions: [s("1")], usage: [], pc: .unknown, now: now)
        let b = WidgetSnapshot.make(sessions: [s("1")], usage: [], pc: .unknown, now: now.addingTimeInterval(30))
        XCTAssertTrue(a.sameContent(as: b))
        XCTAssertNotEqual(a, b)
    }

    func testResetText() {
        XCTAssertEqual(WidgetSnapshot.resetText(now.addingTimeInterval(3 * 3600 + 20 * 60), now: now), "renova em 3h 20min")
        XCTAssertEqual(WidgetSnapshot.resetText(now.addingTimeInterval(2 * 86_400 + 3600), now: now), "renova em 2d 1h")
        XCTAssertEqual(WidgetSnapshot.resetText(now.addingTimeInterval(300), now: now), "renova em 5min")
        XCTAssertNil(WidgetSnapshot.resetText(nil, now: now))
    }
}
