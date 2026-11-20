import XCTest
@testable import AxyomRemoteCore

final class DeepLinkTests: XCTestCase {
    func testRoundTrip() {
        for link in [DeepLink.home, .session("abc-123"), .session("a b/c")] {
            XCTAssertEqual(DeepLink(link.url), link)
        }
    }
    func testRejectsOthers() {
        XCTAssertNil(DeepLink(URL(string: "https://axyom.app/session/1")!))
        XCTAssertNil(DeepLink(URL(string: "axyom://session/")!))
        XCTAssertNil(DeepLink(URL(string: "axyom://other")!))
    }
}
