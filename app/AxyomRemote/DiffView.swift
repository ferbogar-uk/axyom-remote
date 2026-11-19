import SwiftUI
import AxyomRemoteCore

/// The change a file-edit step made: removed lines red, added lines green,
/// at most 40 lines, scrolls sideways for long lines.
struct DiffView: View {
    let diff: FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 6) {
                            Text(mark(line.kind)).foregroundStyle(color(line.kind)).frame(width: 10, alignment: .leading)
                            Text(line.text.isEmpty ? " " : line.text)
                                .foregroundStyle(line.kind == .context || line.kind == .gap ? Theme.muted : Theme.text)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line.kind))
                    }
                }
                .padding(.vertical, 6)
            }
            if diff.truncated {
                Text("Mais alterações no PC").font(.caption2).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alterações em \(diff.path): \(diff.added) linhas acrescentadas, \(diff.removed) removidas")
    }

    private func mark(_ k: FileDiff.Kind) -> String {
        switch k { case .added: "+"; case .removed: "−"; case .context: " "; case .gap: "⋯" }
    }

    private func color(_ k: FileDiff.Kind) -> Color {
        switch k { case .added: .green; case .removed: .red; default: Theme.muted }
    }

    private func background(_ k: FileDiff.Kind) -> Color {
        switch k { case .added: Color.green.opacity(0.12); case .removed: Color.red.opacity(0.12); default: .clear }
    }
}
