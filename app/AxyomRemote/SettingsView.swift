import SwiftUI
import AxyomRemoteCore

/// Only real things here. The mockup's "confirm before running" switch and
/// "connect another PC" row are left out: confirmation is always on, and the
/// server has a single owner and one pairing.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            List {
                Section("PC") {
                    HStack {
                        Text(pcName).foregroundStyle(Theme.text)
                        Spacer()
                        Text(model.pcStatus.isOnline ? "online" : "offline")
                            .font(.subheadline).foregroundStyle(model.pcStatus.isOnline ? Theme.green : Theme.muted)
                    }
                    .listRowBackground(Theme.surface)
                }
                Section("Voz") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Os comandos pedem sempre confirmação").foregroundStyle(Theme.text)
                        Text("Reconhecimento de voz no iPhone, sem enviar o áudio.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(Theme.surface)
                }
                Section("Avisos") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Notificações").foregroundStyle(Theme.text)
                            Spacer()
                            Text("Indisponível").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Text("Precisam de uma alteração no servidor. Por agora, abre a app para ver o que espera por ti.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(Theme.surface)
                }
                Section {
                    Button("Desemparelhar este iPhone", role: .destructive) { confirmUnpair = true }
                        .foregroundStyle(Theme.danger)
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Definições")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
            .confirmationDialog("Desemparelhar este iPhone?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Desemparelhar", role: .destructive) { model.unpair(); dismiss() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Apaga a chave guardada neste iPhone. Para voltar, gera um código novo no PC.")
            }
        }
    }

    private var pcName: String {
        switch model.pcStatus {
        case .online(let name), .offline(let name, _): return name
        case .unknown: return "Nenhum PC visto"
        }
    }
}
