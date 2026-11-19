import XCTest
@testable import AxyomRemoteCore

final class DiffTests: XCTestCase {
    func testEditKeepsOneLineOfContext() {
        let d = FileDiff.edit(path: "a.swift", old: "let a = 1\nlet rate = 1.0\nlet b = 2", new: "let a = 1\nlet rate = Prefs.speed\nlet b = 2")
        XCTAssertEqual(d.lines, [.init(.context, "let a = 1"), .init(.removed, "let rate = 1.0"),
                                 .init(.added, "let rate = Prefs.speed"), .init(.context, "let b = 2")])
        XCTAssertEqual(d.counts, "+1 −1")
    }

    func testClaudeEditStep() {
        let step = Steps.toolStep("Edit", .object(["file_path": .string("/x/SessionView.swift"),
                                                   "old_string": .string("a"), "new_string": .string("a\nb\nc")]))
        XCTAssertEqual(step.text, "Editou SessionView.swift · +2")
        XCTAssertEqual(step.diff?.added, 2)
    }

    func testWriteAndMultiEdit() {
        let w = Steps.toolStep("Write", .object(["file_path": .string("/x/New.md"), "content": .string("# T\nolá")]))
        XCTAssertEqual(w.text, "Criou New.md · +2")
        let m = Steps.toolStep("MultiEdit", .object(["file_path": .string("/x/A.ts"), "edits": .array([
            .object(["old_string": .string("x"), "new_string": .string("y")]),
            .object(["old_string": .string("p\nq"), "new_string": .string("")]),
        ])]))
        XCTAssertEqual(m.diff?.added, 1)
        XCTAssertEqual(m.diff?.removed, 3)
        XCTAssertTrue(m.diff?.lines.contains(.init(.gap, "…")) == true)
    }

    func testUnifiedAndCodexFileChange() {
        let u = "--- a/a.ts\n+++ b/a.ts\n@@ -1,2 +1,2 @@\n ctx\n-old\n+new"
        let d = FileDiff.unified(path: "a.ts", u)
        XCTAssertEqual(d.lines, [.init(.context, "ctx"), .init(.removed, "old"), .init(.added, "new")])
        let raw = #"{"type":"item.completed","item":{"type":"file_change","changes":[{"path":"src/a.ts","diff":"@@ -1 +1 @@\n-old\n+new"}]}}"#
        let steps = Steps.detailed(ChatLines.json(raw)!)
        XCTAssertEqual(steps.first?.text, "Editou a.ts · +1 −1")
    }

    func testLongEditsAreCut() {
        let d = FileDiff.created(path: "big.txt", content: (1...100).map(String.init).joined(separator: "\n"))
        XCTAssertEqual(d.lines.count, 40)
        XCTAssertTrue(d.truncated)
        XCTAssertEqual(d.added, 100)
    }
}
