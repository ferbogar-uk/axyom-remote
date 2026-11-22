import XCTest
@testable import AxyomRemoteCore

final class PCSwitchTests: XCTestCase {
    func device(_ id: String, _ name: String, online: Bool, projects: [String] = []) -> DeviceInfo {
        var d = DeviceInfo(deviceId: id, name: name, type: "desktop", platform: "windows", connectedAt: 0, lastActiveAt: 0)
        d.isOnline = online; d.syncedProjectIds = projects
        return d
    }
    func session(_ id: String, host: String?, enc: String = "e", waiting: Bool = false, archived: Bool = false) -> FleetSession {
        var s = FleetSession(id: id, title: id, projectId: "/p", provider: "claude-code", isExecuting: false, hasPendingPrompt: waiting, isArchived: archived, hostDeviceId: host, lastActivity: Date(), encryptedProjectId: enc)
        s.hostDeviceId = host
        return s
    }

    func testChoicesCountPerPCAndSortOnlineFirst() {
        let devs = [device("b", "Casa", online: false), device("a", "Escritório", online: true),
                    DeviceInfo(deviceId: "m", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)]
        let sessions = [session("1", host: "a", waiting: true), session("2", host: "a"), session("3", host: "b"), session("4", host: "b", archived: true)]
        let c = PCSwitch.choices(devices: devs, sessions: sessions)
        XCTAssertEqual(c.map(\.id), ["a", "b"])
        XCTAssertEqual(c[0].sessionCount, 2); XCTAssertEqual(c[0].attentionCount, 1)
        XCTAssertEqual(c[1].sessionCount, 1, "archived sessions are not counted")
    }

    func testFilterByPCAndFallbacks() {
        let devs = [device("a", "A", online: true, projects: ["encA"]), device("b", "B", online: true, projects: ["encB"])]
        let sessions = [session("1", host: "a"), session("2", host: "b"), session("3", host: nil, enc: "encB")]
        XCTAssertEqual(PCSwitch.filter(sessions, device: "b", devices: devs).map(\.id), ["2", "3"], "no host: the PC that holds the project")
        XCTAssertEqual(PCSwitch.filter(sessions, device: nil, devices: devs).count, 3)
        XCTAssertEqual(PCSwitch.filter(sessions, device: "gone", devices: devs).count, 3, "an unknown PC never empties the list")
    }

    func testPreferredPCWinsWhileOnline() {
        var a = device("a", "A", online: true, projects: ["encA"]); let b = device("b", "B", online: true, projects: ["encB"])
        XCTAssertEqual(DesktopRouting.desktop(forEncryptedProjectId: "encA", devices: [a, b], preferred: "b")?.deviceId, "b")
        a.isOnline = true
        let off = device("b", "B", online: false)
        XCTAssertEqual(DesktopRouting.desktop(forEncryptedProjectId: "encA", devices: [a, off], preferred: "b")?.deviceId, "a", "offline preferred PC is skipped")
    }

    func testNicknameWinsAndBlankIsIgnored() {
        let d = device("a", "DESKTOP-9X", online: true)
        XCTAssertEqual(PCSwitch.displayName(d, nicknames: ["a": " Casa "]), "Casa")
        XCTAssertEqual(PCSwitch.displayName(d, nicknames: ["a": "  "]), "DESKTOP-9X")
        XCTAssertEqual(PCSwitch.choices(devices: [d], sessions: [], nicknames: ["a": "Casa"]).first?.name, "Casa")
    }
}
