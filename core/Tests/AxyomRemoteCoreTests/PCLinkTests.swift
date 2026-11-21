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

    // The reply from the phone screenshot: bare names plus a relative path in code.
    func testRelativePathAndBareNameBecomeLinksWithProjectRoot() {
        let text = "Um PDF no projeto: demo.pdf\n\nCaminho: `packages/extensions/pdf-viewer/samples/demo.pdf`\n\nHá também page-geometry.pdf na mesma pasta."
        let out = Refs.shortenInline(text, root: #"C:\Users\ricar\axyom"#)
        let links = out.components(separatedBy: "(axyom-file:").dropFirst().compactMap { chunk -> String? in
            guard let end = chunk.firstIndex(of: ")"), let u = URL(string: "axyom-file:" + chunk[..<end]) else { return nil }
            return Refs.filePath(from: u)
        }
        let want = #"C:\Users\ricar\axyom\packages\extensions\pdf-viewer\samples\demo.pdf"#
        XCTAssertEqual(links, [want, want], out)                 // the bare name and the path
        XCTAssertTrue(out.contains("[demo.pdf](axyom-file:"), out)
        XCTAssertTrue(out.contains("page-geometry.pdf na mesma"), "a name without a path stays plain")
    }

    func testNoRootMeansRelativePathsStayText() {
        let t = "veja packages/a/demo.pdf"
        XCTAssertEqual(Refs.shortenInline(t), t)
    }

    func testUnixRootAndExistingLinksUntouched() {
        let out = Refs.shortenInline("ver src/app/main.ts e [x](src/app/main.ts)", root: "/home/r/proj/")
        XCTAssertTrue(out.contains("[src/app/main.ts](axyom-file:"), out)
        XCTAssertTrue(out.hasSuffix("[x](src/app/main.ts)"), out)
        XCTAssertEqual(Refs.filePath(from: URL(string: String(out[out.range(of: "axyom-file:[^)]+", options: .regularExpression)!]))!), "/home/r/proj/src/app/main.ts")
    }
}
