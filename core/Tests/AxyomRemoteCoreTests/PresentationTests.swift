import XCTest
@testable import AxyomRemoteCore

final class PresentationTests: XCTestCase {
    private func device(_ name: String, type: String = "desktop", online: Bool?, lastActive: Double) -> DeviceInfo {
        var d = DeviceInfo(deviceId: name, name: name, type: type, platform: "win32", connectedAt: 0, lastActiveAt: lastActive)
        d.isOnline = online
        return d
    }

    func testOnlineDesktopWins() {
        let status = PCStatus.from(devices: [
            device("Old PC", online: false, lastActive: 5_000),
            device("Home Laptop", online: true, lastActive: 1_000),
        ])
        XCTAssertEqual(status, .online(name: "Home Laptop"))
        XCTAssertTrue(status.isOnline)
    }

    func testOfflineUsesMostRecentDesktop() {
        let status = PCStatus.from(devices: [
            device("Old PC", online: false, lastActive: 5_000),
            device("Home Laptop", online: false, lastActive: 90_000),
        ])
        XCTAssertEqual(status, .offline(name: "Home Laptop", lastSeen: Date(timeIntervalSince1970: 90)))
        XCTAssertFalse(status.isOnline)
    }

    func testPhonesAreNotThePC() {
        XCTAssertEqual(PCStatus.from(devices: [device("iPhone", type: "mobile", online: true, lastActive: 1)]), .unknown)
        XCTAssertEqual(PCStatus.from(devices: []), .unknown)
    }

    func testRelativeAgeInPortuguese() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func age(_ secondsAgo: Double) -> String {
            RelativeAge.portuguese(from: now.addingTimeInterval(-secondsAgo), now: now)
        }
        XCTAssertEqual(age(10), "agora")
        XCTAssertEqual(age(12 * 60), "há 12 min")
        XCTAssertEqual(age(3 * 3600), "há 3 h")
        XCTAssertEqual(age(86_400), "há 1 dia")
        XCTAssertEqual(age(3 * 86_400), "há 3 dias")
        XCTAssertEqual(age(-30), "agora")
    }

    func testProviderNames() {
        XCTAssertEqual(ProviderName.display("openai-codex"), "Codex")
        XCTAssertEqual(ProviderName.display("claude-code"), "Claude")
        XCTAssertEqual(ProviderName.display("opencode"), "OpenCode")
        XCTAssertEqual(ProviderName.display("something-new"), "something-new")
    }
}
