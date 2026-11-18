import SwiftUI

/// Renders the agent's Markdown the way the desktop does, enough for a phone:
/// headings, bullet and numbered lists, **bold** / *italic* / `code` / links,
/// and fenced code blocks in a scrollable monospaced box.
struct MarkdownText: View {
    let text: String
    var color: Color = Theme.textSoft

    private enum Block: Hashable {
        case paragraph(String)
        case heading(String, level: Int)
        case bullet(String, marker: String)
        case code(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6, line.dropFirst(level).first == " " {
                    flush(); out.append(.heading(String(line.dropFirst(level + 1)), level: level)); continue
                }
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush(); out.append(.bullet(String(line.dropFirst(2)), marker: "•")); continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].first == " " {
                flush(); out.append(.bullet(String(line[line.index(dot, offsetBy: 2)...]), marker: String(line[...dot]))); continue
            }
            paragraph.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    Text(inline(s)).font(.body).foregroundStyle(color)
                case .heading(let s, let level):
                    Text(inline(s)).font(level <= 2 ? .headline : .subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                case .bullet(let s, let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).font(.body).foregroundStyle(Theme.muted)
                        Text(inline(s)).font(.body).foregroundStyle(color)
                    }
                case .code(let s):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(s).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.text)
                            .padding(10)
                    }
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
