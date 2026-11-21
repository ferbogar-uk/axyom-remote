import SwiftUI
import UIKit
import AxyomRemoteCore

/// Cards under an agent reply for what it mentions: web pages (open in
/// Safari), pictures on the web (thumbnail), and files or screenshots on the
/// PC (name and folder; the phone cannot open PC files yet, so tapping copies
/// the full path).
struct RefCards: View {
    let refs: [Refs.Ref]
    var sessionId: String? = nil
    var target: String? = nil
    @EnvironmentObject private var model: AppModel
    @State private var copied: String?
    @State private var viewing: Data?

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
            .fullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) { viewer }
        }
    }

    private var viewer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let data = viewing, let image = UIImage(data: data) {
                ScrollView([.horizontal, .vertical]) { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity) }
            }
            Button { viewing = nil } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.85)).padding() }
                .accessibilityLabel("Fechar")
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

    /// A picture or PDF on the PC: ask the PC for a small preview only when you tap, then show it.
    private func pcPreview(_ ref: Refs.Ref, content: some View) -> some View {
        let key = sessionId.map { AppModel.previewKey($0, ref.target) } ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            if let data = model.filePreviews[key], let image = UIImage(data: data) {
                Button { viewing = data } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pré-visualização de \(ref.title). Toca para ampliar")
            }
            Button {
                if let sid = sessionId { model.requestPreview(sessionId: sid, path: ref.target, target: target) }
            } label: { content }
            .buttonStyle(.plain)
            .disabled(model.filePreviews[key] != nil || model.previewWaiting.contains(key))
            if model.previewWaiting.contains(key) {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("A pedir ao PC…").font(.caption).foregroundStyle(Theme.muted) }
            } else if model.previewFailed.contains(key) {
                Text("O PC não enviou a pré-visualização (ficheiro fora do projeto, grande demais ou PC desligado).")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
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
            Image(systemName: ref.kind == .web ? "arrow.up.right" : (sessionId != nil && FilePreview.canPreview(ref.target) ? "eye" : (copied == ref.target ? "checkmark" : "doc.on.doc")))
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        if ref.kind == .web, let url = URL(string: ref.target) {
            Link(destination: url) { content }.accessibilityLabel("Abrir \(ref.title)")
        } else if sessionId != nil, FilePreview.canPreview(ref.target) {
            pcPreview(ref, content: content)
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
        case .pcImage: return (sessionId != nil ? "Toca para ver · " : "Imagem no PC · ") + (ref.folder ?? "")
        case .file: return (sessionId != nil && FilePreview.canPreview(ref.target) ? "Toca para ver · " : "No PC · ") + (ref.folder ?? "")
        }
    }
}
