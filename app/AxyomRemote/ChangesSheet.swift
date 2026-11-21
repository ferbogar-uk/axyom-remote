import SwiftUI
import AxyomRemoteCore

/// Everything the agent changed in this session, file by file. "Revisto" is a tick kept on the
/// phone only (it does not touch the PC); "Pedir para desfazer" writes the request for the agent
/// into the reply box, so nothing is sent until you press send.
struct ChangesSheet: View {
    let sessionId: String
    let changes: [FileChange]
    let onUndo: (FileChange) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reviewed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "reviewedChanges") ?? [])

    private func key(_ c: FileChange) -> String { "\(sessionId)|\(c.path)|\(c.diff.added)|\(c.diff.removed)" }

    var body: some View {
        NavigationStack {
            List {
                let t = ChangedFiles.totals(changes)
                Section {
                    ForEach(changes) { c in
                        NavigationLink {
                            FileChangeDetail(change: c, reviewed: reviewed.contains(key(c)),
                                             toggleReviewed: { toggle(c) }, onUndo: { dismiss(); onUndo(c) })
                        } label: { row(c) }
                        .listRowBackground(Theme.surface)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("\(changes.count) \(changes.count == 1 ? "ficheiro" : "ficheiros")")
                        Text("+\(t.added)").foregroundStyle(.green)
                        Text("−\(t.removed)").foregroundStyle(.red)
                        Spacer()
                        Text("\(changes.filter { reviewed.contains(key($0)) }.count)/\(changes.count) revistos")
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Alterações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } } }
            .overlay { if changes.isEmpty { Text("O agente ainda não alterou ficheiros nesta sessão.").font(.subheadline).foregroundStyle(Theme.muted).padding() } }
        }
    }

    private func row(_ c: FileChange) -> some View {
        HStack(spacing: 12) {
            Image(systemName: reviewed.contains(key(c)) ? "checkmark.circle.fill" : "doc.text")
                .foregroundStyle(reviewed.contains(key(c)) ? Color.green : Theme.textSoft)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.subheadline).foregroundStyle(Theme.text).lineLimit(1)
                Text((c.folder ?? "") + (c.edits > 1 ? " · \(c.edits) edições" : "")).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if c.diff.added > 0 { Text("+\(c.diff.added)").foregroundStyle(.green) }
                if c.diff.removed > 0 { Text("−\(c.diff.removed)").foregroundStyle(.red) }
            }
            .font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ c: FileChange) {
        let k = key(c)
        if reviewed.contains(k) { reviewed.remove(k) } else { reviewed.insert(k) }
        UserDefaults.standard.set(Array(reviewed), forKey: "reviewedChanges")
        Prefs.tap()
    }
}

private struct FileChangeDetail: View {
    let change: FileChange
    let reviewed: Bool
    let toggleReviewed: () -> Void
    let onUndo: () -> Void
    @State private var isReviewed: Bool

    init(change: FileChange, reviewed: Bool, toggleReviewed: @escaping () -> Void, onUndo: @escaping () -> Void) {
        self.change = change; self.reviewed = reviewed; self.toggleReviewed = toggleReviewed; self.onUndo = onUndo
        _isReviewed = State(initialValue: reviewed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(change.path).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.muted).textSelection(.enabled)
                DiffView(diff: change.diff)
                Button {
                    isReviewed.toggle(); toggleReviewed()
                } label: {
                    Label(isReviewed ? "Revisto" : "Marcar como revisto", systemImage: isReviewed ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(isReviewed ? .green : Theme.accent)
                Button(role: .destructive, action: onUndo) {
                    Label("Pedir ao agente para desfazer", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                Text("“Revisto” fica só neste iPhone. “Desfazer” escreve o pedido na caixa de resposta; só vai quando carregares em enviar.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(change.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
