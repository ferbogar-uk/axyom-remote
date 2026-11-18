import SwiftUI
import AxyomRemoteCore

/// Facts about a session, from the index the PC publishes.
struct SessionInfoSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    let modelName: String

    private var session: FleetSession? { model.snapshot.sessions.first { $0.id == sessionId } }
    private var pcName: String {
        guard let host = session?.hostDeviceId else { return "—" }
        return model.snapshot.devices.first { $0.deviceId == host }?.name ?? "PC (desligado)"
    }

    var body: some View {
        NavigationStack {
            List {
                if let s = session {
                    Section {
                        HStack(spacing: 12) {
                            AgentBadge(provider: s.provider, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.headline).foregroundStyle(Theme.text)
                                Text(ProviderName.display(s.provider)).font(.subheadline).foregroundStyle(Theme.muted)
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                    Section {
                        fact("Projeto", s.projectName)
                        fact("Pasta", s.projectId)
                        fact("PC", pcName)
                        fact("Modelo", modelName)
                        fact("Esforço", ModelPicker.effortLabel(s.effortLevel) ?? "O padrão do PC")
                        fact("Estado", s.hasPendingPrompt ? "À espera de ti" : s.isExecuting ? "A trabalhar" : "Parada")
                        if let n = s.messageCount { fact("Mensagens", "\(n)") }
                        if s.queuedPromptCount > 0 { fact("Na fila", "\(s.queuedPromptCount)") }
                        if let c = s.createdAt { fact("Criada", c.formatted(date: .abbreviated, time: .shortened)) }
                        fact("Última atividade", RelativeAge.portuguese(from: s.lastActivity))
                    }
                    Section {
                        Button { UIPasteboard.general.string = s.id; Prefs.tap() } label: {
                            Label("Copiar o ID da sessão", systemImage: "doc.on.doc")
                        }
                        .foregroundStyle(Theme.text)
                        .listRowBackground(Theme.surface)
                    }
                } else {
                    Text("Esta sessão já não está na lista.").foregroundStyle(Theme.muted).listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Informação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Theme.text) }
                        .accessibilityLabel("Fechar")
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Theme.text).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .listRowBackground(Theme.surface)
    }
}
