import XCTest
@testable import AxyomRemoteCore

final class PCLinkTests: XCTestCase {
    func path(_ s: String) -> String? {
        guard let r = s.range(of: #"axyom-file:[^)]+"#, options: .regularExpression), let u = URL(string: String(s[r])) else { return nil }
        return Refs.filePath(from: u)
    }

    func testWindowsPathInMarkdownLinkBecomesTappable() {
        let out = Refs.shortenInline(#"- [demo.pdf](C:\Users\ricar\axyom\demo.pdf)"#)
        XCTAssertTrue(out.hasPrefix("- [demo.pdf](axyom-file:"), out)
        XCTAssertEqual(path(out), #"C:\Users\ricar\axyom\demo.pdf"#)
    }

    func testUnixAndFileURLLinks() {
        XCTAssertEqual(path(Refs.shortenInline("[a](/home/x/a.png)")), "/home/x/a.png")
        XCTAssertEqual(path(Refs.shortenInline("[a](file:///C:/Users/x/a.pdf)")), "C:/Users/x/a.pdf")
    }

    func testWebLinksAndRelativePathsUntouched() {
        XCTAssertEqual(Refs.linkPCPaths(in: "[x](https://a.com/p.pdf)"), "[x](https://a.com/p.pdf)")
        XCTAssertEqual(Refs.linkPCPaths(in: "[x](packages/a/demo.pdf)"), "[x](packages/a/demo.pdf)")
    }
}
