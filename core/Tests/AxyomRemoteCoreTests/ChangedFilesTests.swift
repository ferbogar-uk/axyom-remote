import XCTest
@testable import AxyomRemoteCore

final class ChangedFilesTests: XCTestCase {
    func step(_ id: String, _ path: String, old: String, new: String) -> ChatLine {
        ChatLine(id: id, mine: false, text: "Editou", isStep: true, diff: FileDiff.edit(path: path, old: old, new: new))
    }

    func testJoinsEditsOfTheSameFileAndOrdersByLatest() {
        let lines = [
            step("1", "/p/a.swift", old: "x", new: "y"),
            step("2", "/p/b.swift", old: "", new: "novo"),
            step("3", "/p/a.swift", old: "1", new: "2\n3"),
            ChatLine(id: "4", mine: false, text: "Olá"),
        ]
        let c = ChangedFiles.build(lines)
        XCTAssertEqual(c.map(\.path), ["/p/a.swift", "/p/b.swift"])
        XCTAssertEqual(c[0].edits, 2)
        XCTAssertEqual(c[0].diff.added, 3)
        XCTAssertEqual(c[0].diff.removed, 2)
        XCTAssertEqual(c[0].name, "a.swift")
        XCTAssertEqual(c[1].edits, 1)
        let t = ChangedFiles.totals(c)
        XCTAssertEqual(t.added, 4); XCTAssertEqual(t.removed, 2)
    }

    func testNoEditsMeansNoFiles() {
        XCTAssertTrue(ChangedFiles.build([ChatLine(id: "1", mine: false, text: "Oi")]).isEmpty)
    }

    func testFolderShowsLastTwoParts() {
        let c = ChangedFiles.build([step("1", #"C:\Users\x\src\components\Btn.tsx"#, old: "a", new: "b")])
        XCTAssertEqual(c[0].folder, "src/components")
    }
}
