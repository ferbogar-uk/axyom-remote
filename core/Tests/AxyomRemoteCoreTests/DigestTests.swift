import XCTest
@testable import AxyomRemoteCore

final class DigestTests: XCTestCase {
    func testBackgroundNoticeBecomesOneStep() {
        let raw = """
        [Background tasks finished:
        - "cd "C:/Users/ricar/PROJECTS/AXYOM - AI Development OS" && git ls-files | grep -E '\\.(ts)$'" completed
          Summary: cd ...
        - "Analisar repositório AXYOM" completed
          Summary: This agent's report was delivered to you as a message from "acad7140c0160ba33" (its SubagentHandback call).
          Output file: C:\\Users\\ricar\\AppData\\Local\\Temp\\claude\\x.output
        Continue the work that was waiting on them.]
        """
        XCTAssertEqual(Notices.summary(raw), "Tarefa em segundo plano terminou: Analisar repositório AXYOM")
        XCTAssertNil(Notices.summary("Olá, corre os testes"))

        let items = [
            TranscriptItem(id: "1", sequence: 1, createdAt: Date(), source: "x", direction: "input", hidden: false, raw: raw, text: raw),
            TranscriptItem(id: "2", sequence: 2, createdAt: Date(), source: "x", direction: "output", hidden: false, raw: "A análise terminou.", text: "A análise terminou."),
        ]
        let lines = ChatLines.build(items, provider: "claude-code", includeSteps: true)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].isStep)
        XCTAssertFalse(lines[0].mine)
        XCTAssertNotNil(lines[0].detail)
        XCTAssertEqual(ChatLines.build(items, provider: "claude-code").map(\.text), ["A análise terminou."])
    }

    func testCommandsInPlainPortuguese() {
        XCTAssertEqual(Steps.command(#"cd "C:/x" && git status --short | wc -l"#, description: nil), "Viu o estado do git")
        XCTAssertEqual(Steps.command(#"$l=Get-ChildItem "$env:APPDATA\AXYOM\logs""#, description: nil), "Viu os registos")
        XCTAssertEqual(Steps.command("pnpm vitest run", description: nil), "Correu os testes")
        XCTAssertEqual(Steps.command("weird-tool --x", description: "Check the cache"), "Check the cache")
        XCTAssertEqual(Steps.command("weird-tool --x", description: nil), "Correu um comando")
        let step = Steps.toolStep("mcp__remote-devices__plugin_8d52a3a6-3a2d-4a54-8d1d-e08585a97642_desktop-commander__start_process",
                                  .object(["command": .string("git log --oneline -5")]))
        XCTAssertEqual(step.text, "Viu o histórico do git")
        XCTAssertEqual(step.detail, "git log --oneline -5")
        let other = Steps.toolStep("mcp__claude-artifacts__publish_files", nil)
        XCTAssertFalse(other.text.contains("8d52"))
        XCTAssertEqual(other.text, "Usou publish files")
    }

    func testRefsFindsLinksFilesAndPictures() {
        let text = """
        Vê https://github.com/ferbogar-uk/axyom-remote/pull/3. O print está em C:\\Users\\ricar\\Pictures\\shot.png
        e o relatório em /Users/ricardo/Docs/report.pdf, mais https://example.com/a.jpg
        """
        let refs = Refs.find(text)
        XCTAssertEqual(refs.map(\.kind), [.web, .image, .pcImage, .file])
        XCTAssertEqual(refs[0].title, "github.com/ferbogar-uk/axyom-remote/pull/3")
        XCTAssertEqual(refs[2].title, "shot.png")
        XCTAssertEqual(refs[2].folder, "ricar/Pictures")
        XCTAssertEqual(Refs.find("sem nada aqui"), [])
    }
}

final class ShortLinkTests: XCTestCase {
    func testLinksAndPathsBecomeShortMarkdownLinks() {
        let s = Refs.shortenInline("Vê https://github.com/ferbogar-uk/axyom-remote/pull/8 e C:\\Users\\ricar\\Pictures\\voz.png.")
        XCTAssertTrue(s.contains("[pull/8](https://github.com/ferbogar-uk/axyom-remote/pull/8)"), s)
        XCTAssertTrue(s.contains("[voz.png](axyom-file:"), s)
        let url = URL(string: String(s[s.range(of: "axyom-file:")!.lowerBound...].prefix { $0 != ")" }))!
        XCTAssertEqual(Refs.filePath(from: url), "C:\\Users\\ricar\\Pictures\\voz.png")
        XCTAssertEqual(Refs.shortenInline("[site](https://example.com/a)"), "[site](https://example.com/a)")
    }
}
