import SwiftUI
import UIKit
import AxyomRemoteCore

/// A file named in an agent's reply, opened from the name in the text. Pictures and PDFs are
/// fetched from the PC when the sheet opens (you tapped, so you asked); other files show their
/// full path, because the PC only sends pictures and PDFs for now.
struct PCFileSheet: View {
    let path: String
    let sessionId: String
    let target: String?
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var key: String { AppModel.previewKey(sessionId, path) }
    private var name: String { (path as NSString).lastPathComponent.isEmpty ? path : path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                content
                Button {
                    UIPasteboard.general.string = path; copied = true; Prefs.tap()
                } label: {
                    Label(copied ? "Caminho copiado" : "Copiar caminho no PC", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                Text(path).font(.caption2).foregroundStyle(Theme.muted).lineLimit(3).textSelection(.enabled)
            }
            .padding()
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } } }
        }
        .onAppear {
            if FilePreview.canPreview(path) || FilePreview.canText(path) { model.requestPreview(sessionId: sessionId, path: path, target: target) }
        }
    }

    @ViewBuilder private var content: some View {
        if !FilePreview.canPreview(path), !FilePreview.canText(path) {
            note("O PC só envia imagens, PDFs e ficheiros de texto ou código. Este tipo não se vê no iPhone.", icon: "doc.text")
        } else if let file = model.fileTexts[key] {
            ScrollView([.horizontal, .vertical]) {
                Text(file.text).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.text)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if file.truncated { Text("Ficheiro grande: só o início (200 KB).").font(.caption).foregroundStyle(Theme.muted) }
        } else if let data = model.filePreviews[key], let image = UIImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if model.previewFailed.contains(key) {
            VStack(spacing: 10) {
                note("O PC não enviou a pré-visualização. Pode ser um AXYOM desatualizado no PC, o ficheiro estar fora do projeto, ser grande demais ou o PC estar desligado.", icon: "exclamationmark.triangle")
                Button("Tentar outra vez") { model.requestPreview(sessionId: sessionId, path: path, target: target) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        } else {
            VStack(spacing: 10) { ProgressView(); Text("A pedir ao PC…").font(.subheadline).foregroundStyle(Theme.muted) }
                .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private func note(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.muted)
            Text(text).font(.subheadline).foregroundStyle(Theme.textSoft).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
