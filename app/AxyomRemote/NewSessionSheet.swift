import SwiftUI
import AxyomRemoteCore

/// Starts a session on the PC through `RemoteClient.createSession`. That call
/// waits up to 30 s for the desktop's answer, and so does the label below.
struct NewSessionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let board: FleetBoard

    private static let agents: [VoiceAgent] = [.claude, .codex, .grok, .opencode]

    @State private var projectId: String?
    @State private var agent: VoiceAgent = .claude
    @State private var prompt = ""
    @State private var sending = false
    @State private var failure: String?
    @State private var modelId: String?

    private var models: [PlanUsage.ModelChoice] {
        let all = model.snapshot.planUsage.first(where: { !$0.models.isEmpty })?.models ?? []
        return ModelPicker.choices(for: agent.providerId, in: all)
    }

    private var canStart: Bool {
        projectId != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending && model.pcStatus.isOnline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Nova sessão no PC").font(.title3.bold()).foregroundStyle(Theme.text)
                Spacer()
                Button("Cancelar") { dismiss() }.foregroundStyle(Theme.muted).frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Projeto").font(.footnote).foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(board.projects) { p in
                            Button { projectId = p.id } label: {
                                Text(p.name).font(.subheadline.weight(projectId == p.id ? .semibold : .regular))
                                    .foregroundStyle(projectId == p.id ? Theme.amberLight : Theme.text)
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .background(projectId == p.id ? Theme.amberFill : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(projectId == p.id ? Theme.amber : Theme.borderStrong, lineWidth: 1))
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Agente").font(.footnote).foregroundStyle(Theme.muted)
                Picker("Agente", selection: $agent) {
                    ForEach(Self.agents, id: \.self) { Text(ProviderName.display($0.providerId)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: agent) { _, _ in modelId = nil }
                if !models.isEmpty {
                    Menu {
                        Button { modelId = nil } label: {
                            if modelId == nil { Label("O padrão do PC", systemImage: "checkmark") } else { Text("O padrão do PC") }
                        }
                        ForEach(models) { m in
                            Button { modelId = m.id } label: {
                                if modelId == m.id { Label(m.name, systemImage: "checkmark") } else { Text(m.name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Modelo").foregroundStyle(Theme.muted)
                            Text(models.first(where: { $0.id == modelId })?.name ?? "O padrão do PC").foregroundStyle(Theme.text)
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Theme.elevated, in: Capsule())
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("O que queres que faça?").font(.footnote).foregroundStyle(Theme.muted)
                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .frame(minHeight: 140)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
            }
            if let failure { Text(failure).font(.subheadline).foregroundStyle(Theme.danger) }
            Spacer(minLength: 0)
            Button(sending ? "A pedir ao PC…" : "Começar no PC") { Task { await start() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canStart)
            Text("O PC tem 30 segundos para responder. Se não responder, dizemos-te aqui.")
                .font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(Theme.surface)
        .presentationDetents([.large])
        .onAppear { projectId = projectId ?? board.projects.first?.id }
    }

    private func start() async {
        guard let client = model.client, let projectId else { return }
        sending = true; failure = nil
        defer { sending = false }
        do {
            _ = try await client.createSession(
                projectId: projectId,
                provider: agent.providerId,
                model: modelId,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                targetDeviceId: model.desktopId(forEncryptedProjectId: board.projects.first(where: { $0.id == projectId })?.encryptedId)
            )
            dismiss()
        } catch RemoteClient.ClientError.timeout {
            failure = "O PC não respondeu em 30 segundos. Confirma que o AXYOM está aberto."
        } catch RemoteClient.ClientError.refused(let why) {
            failure = "O PC recusou: \(why)"
        } catch {
            failure = "Não consegui falar com o PC. Tenta outra vez."
        }
    }
}
