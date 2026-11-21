import SwiftUI
import AxyomRemoteCore
import UIKit

/// Renders the agent's Markdown the way the desktop does, enough for a phone:
/// headings, bullet and numbered lists, **bold** / *italic* / `code` / links,
/// and fenced code blocks in a scrollable monospaced box.
struct MarkdownText: View {
    let text: String
    var color: Color = Theme.textSoft
    /// The session's folder, to turn paths written inside the project into tappable files.
    var projectRoot: String? = nil
    /// Code blocks start folded ("Código · 12 linhas"); tapped ones open.
    @State private var openCode: Set<Int> = []

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
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
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
                    codeBlock(s, index: index)
                }
            }
        }
        // PC files: tapping the name opens the viewer (a picture or PDF comes from the PC, request #9).
        .environment(\.openURL, OpenURLAction { url in
            if let path = Refs.filePath(from: url) { Prefs.tap(); AppModel.shared.openFilePath = path; return .handled }
            return .systemAction
        })
        .textSelection(.enabled)
    }

    @ViewBuilder private func codeBlock(_ s: String, index: Int) -> some View {
        let open = openCode.contains(index)
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).count
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if open { openCode.remove(index) } else { openCode.insert(index) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.caption)
                    Text("Código · \(lines) \(lines == 1 ? "linha" : "linhas")").font(.footnote)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).rotationEffect(.degrees(open ? 90 : 0))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Esconder código" : "Mostrar código, \(lines) linhas")
            if open {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(s).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func inline(_ s: String) -> AttributedString {
        let short = Refs.shortenInline(s, root: projectRoot)
        guard var out = try? AttributedString(markdown: short, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return AttributedString(s) }
        // Links read as links, in the brand amber, like the orange file names on the PC.
        for run in out.runs where run.link != nil {
            out[run.range].foregroundColor = Theme.accent
            out[run.range].underlineStyle = .single
        }
        return out
    }
}
