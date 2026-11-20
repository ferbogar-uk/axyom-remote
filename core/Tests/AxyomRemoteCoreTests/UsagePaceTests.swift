import XCTest
@testable import AxyomRemoteCore

final class UsagePaceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMarkMovesHourByHourInTheFiveHourWindow() {
        // 30 min into the window → mark at the end of hour 1 = 20 %.
        let r1 = UsagePace.read(name: "Session", percent: 15, resetsAt: now.addingTimeInterval(4.5 * 3600), now: now)
        XCTAssertEqual(r1.mark!, 0.2, accuracy: 0.001)
        XCTAssertEqual(r1.status, .ok)
        XCTAssertEqual(UsagePace.read(name: "Session", percent: 25, resetsAt: now.addingTimeInterval(4.5 * 3600), now: now).status, .ahead)
        // 1 h 10 min in → hour 2 → 40 %.
        let r2 = UsagePace.read(name: "5-hour", percent: 35, resetsAt: now.addingTimeInterval(3 * 3600 + 50 * 60), now: now)
        XCTAssertEqual(r2.mark!, 0.4, accuracy: 0.001)
        XCTAssertEqual(r2.status, .ok)
    }

    func testWeeklyStepsByDayAndRedFrom80() {
        let r = UsagePace.read(name: "Weekly", percent: 31, resetsAt: now.addingTimeInterval(5 * 86400 + 17 * 3600), now: now)
        XCTAssertEqual(r.mark!, 2.0 / 7.0, accuracy: 0.001)    // day 2 of 7
        XCTAssertEqual(r.status, .ahead)
        XCTAssertEqual(r.windowLabel, "7 dias")
        XCTAssertEqual(UsagePace.read(name: "Weekly", percent: 82, resetsAt: nil, now: now).status, .critical)
        XCTAssertNil(UsagePace.read(name: "Mystery", percent: 10, resetsAt: now, now: now).mark)
    }
}
