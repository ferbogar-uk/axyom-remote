import XCTest
@testable import AxyomRemoteCore

final class SessionTreeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func s(_ id: String, _ hoursAgo: Double, parent: String? = nil, role: String? = nil, phase: String? = nil) -> FleetSession {
        var x = FleetSession(id: id, title: id, projectId: "p", provider: "claude-code", lastActivity: now.addingTimeInterval(-hoursAgo * 3600))
        x.parentId = parent; x.agentRole = role; x.phase = phase
        return x
    }

    func testChildrenNestUnderParentAndFamilyTakesNewestDate() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let list = [s("aion", 30, role: "meta-agent", phase: "implementing"), s("oi", 0.1, parent: "aion"),
                    s("sub2", 50, parent: "aion"), s("analise", 1, phase: "planning"), s("old", 24 * 10)]
        let sections = SessionTree.build(list, now: now, calendar: cal)
        XCTAssertEqual(sections.map(\.title), ["Hoje", "Antes"])
        let today = sections[0].rows
        XCTAssertEqual(today.map(\.id), ["aion", "oi", "sub2", "analise"])
        XCTAssertEqual(today[0].role, "Orquestrador")
        XCTAssertEqual(today[0].phase, "A implementar")
        XCTAssertEqual(today[0].childCount, 2)
        XCTAssertEqual(today[1].depth, 1)
        XCTAssertEqual(today[1].role, "Sub-agente")
        XCTAssertEqual(today[3].phase, "Planeamento")
    }

    func testCollapsedParentHidesChildrenAndOrphansAreRoots() {
        let list = [s("a", 1), s("b", 2, parent: "a"), s("c", 3, parent: "missing")]
        let rows = SessionTree.build(list, collapsed: ["a"], now: now).flatMap(\.rows)
        XCTAssertEqual(rows.map(\.id), ["a", "c"])
        XCTAssertEqual(rows[0].childCount, 1)
    }
}
