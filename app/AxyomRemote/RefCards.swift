import SwiftUI
import UIKit
import AxyomRemoteCore

/// Cards under an agent reply for what it mentions: web pages (open in
/// Safari), pictures on the web (thumbnail), and files or screenshots on the
/// PC (name and folder; the phone cannot open PC files yet, so tapping copies
/// the full path).
struct RefCards: View {
    let refs: [Refs.Ref]
    @State private var copied: String?

    var body: some View {
        if !refs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                let pictures = refs.filter { $0.kind == .image }
                if !pictures.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(pictures) { thumbnail($0) } }
                    }
                }
                ForEach(refs.filter { $0.kind != .image }) { card($0) }
            }
        }
    }

    private func thumbnail(_ ref: Refs.Ref) -> some View {
        Link(destination: URL(string: ref.target)!) {
            AsyncImage(url: URL(string: ref.target)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Theme.elevated.overlay(Image(systemName: "photo").foregroundStyle(Theme.muted)) }
            }
            .frame(width: 120, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Imagem: \(ref.title)")
    }

    @ViewBuilder private func card(_ ref: Refs.Ref) -> some View {
        let icon: String = switch ref.kind {
        case .web: "globe"
        case .pcImage: "photo.on.rectangle"
        default: ref.target.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc.text"
        }
        let content = HStack(spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(Theme.textSoft)
                .frame(width: 34, height: 34)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.title).font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle(ref)).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: ref.kind == .web ? "arrow.up.right" : (copied == ref.target ? "checkmark" : "doc.on.doc"))
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        if ref.kind == .web, let url = URL(string: ref.target) {
            Link(destination: url) { content }.accessibilityLabel("Abrir \(ref.title)")
        } else {
            Button {
                UIPasteboard.general.string = ref.target
                copied = ref.target
            } label: { content }
            .buttonStyle(.plain)
            .accessibilityLabel("\(ref.title), no PC. Copiar caminho")
        }
    }

    private func subtitle(_ ref: Refs.Ref) -> String {
        switch ref.kind {
        case .web, .image: return "Abrir no Safari"
        case .pcImage: return "Imagem no PC · " + (ref.folder ?? "")
        case .file: return "No PC · " + (ref.folder ?? "")
        }
    }
}
