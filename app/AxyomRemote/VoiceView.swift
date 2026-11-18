import SwiftUI
import AxyomRemoteCore

/// Voice command with confirmation. Only "new session" can run from the phone
/// today; approve, deny and reply need the desktop payloads (HANDOFF section 8)
/// and are explained, not faked.
struct VoiceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var listener = SpeechListener()
    @State private var sending = false
    @State private var failure: String?

    private var board: FleetBoard { model.board() }

    private var intent: VoiceIntent? {
        let text = listener.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !listener.listening, !text.isEmpty else { return nil }
        return VoiceCommandParser(knownProjects: board.projects.map(\.name)).parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Voz").font(.title3.bold()).foregroundStyle(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44).foregroundStyle(Theme.text)
                        .background(Theme.surface, in: Circle()).overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .accessibilityLabel("Fechar")
            }
            if listener.transcript.isEmpty && listener.problem == nil {
                Text(listener.listening ? "A ouvir…" : "Toca no microfone e diz o que queres.")
                    .font(.body).foregroundStyle(Theme.muted)
            } else if !listener.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tu disseste").font(.caption).foregroundStyle(Theme.muted)
                    Text("“\(listener.transcript)”").font(.body).foregroundStyle(Theme.textSoft)
                }
                .card()
            }
            if let problem = listener.problem { Text(problem).font(.subheadline).foregroundStyle(Theme.danger) }
            if let intent { understood(intent) }
            if let failure { Text(failure).font(.subheadline).foregroundStyle(Theme.danger) }
            Text("Nada é enviado ao PC até confirmares. O reconhecimento de voz corre no iPhone.")
                .font(.footnote).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button { listener.toggle() } label: {
                    Image(systemName: listener.listening ? "stop.fill" : "mic.fill").font(.system(size: 34))
                        .foregroundStyle(Theme.onAmber).frame(width: 96, height: 96)
                        .background(Theme.amber, in: Circle())
                }
                .accessibilityLabel(listener.listening ? "Parar de ouvir" : "Falar")
                Text(listener.listening ? "Toca para parar" : "Toca para falar").font(.subheadline).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(Theme.background)
        .onDisappear { listener.stop() }
    }

    @ViewBuilder private func understood(_ intent: VoiceIntent) -> some View {
        switch intent {
        case .newSession(let agent, let project, let prompt):
            let target = resolve(project)
            VStack(alignment: .leading, spacing: 12) {
                Text("Entendi isto").sectionLabel(Theme.amber)
                fact("Ação", "Nova sessão")
                fact("Agente", agent.map { ProviderName.display($0.providerId) } ?? "Claude")
                fact("Projeto", target?.name ?? "Diz em que projeto. Exemplo: \"no \(board.projects.first?.name ?? "AXYOM")\".")
                fact("Pedido", prompt)
                HStack(spacing: 8) {
                    Button(sending ? "A pedir ao PC…" : "Confirmar e começar") {
                        if let target { Task { await start(agent: agent ?? .claude, project: target.id, prompt: prompt) } }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(target == nil || sending || !model.pcStatus.isOnline)
                    Button("Cancelar") { listener.transcript = "" }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 110)
                }
            }
            .card(fill: Theme.amberSurface, stroke: Theme.amberBorder)
        case .approve, .deny, .reply:
            Text("Responder e aprovar a partir do iPhone ainda não está disponível. Faz-o no PC por agora.")
                .font(.subheadline).foregroundStyle(Theme.textSoft).card()
        case .status:
            Text("À espera de ti: \(board.waiting.count). A trabalhar: \(board.working.count).")
                .font(.subheadline).foregroundStyle(Theme.textSoft).card()
        case .empty:
            Text("Não percebi nada. Tenta outra vez.").font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(Theme.muted).frame(width: 72, alignment: .leading)
            Text(value).font(.body).foregroundStyle(Theme.text)
        }
    }

    private func resolve(_ spoken: String?) -> FleetBoard.Project? {
        guard let spoken else { return board.projects.count == 1 ? board.projects.first : nil }
        return board.projects.first { $0.name.caseInsensitiveCompare(spoken) == .orderedSame }
    }

    private func start(agent: VoiceAgent, project: String, prompt: String) async {
        guard let client = model.client else { return }
        sending = true; failure = nil
        defer { sending = false }
        do {
            _ = try await client.createSession(projectId: project, provider: agent.providerId, prompt: prompt, targetDeviceId: model.desktopDeviceId)
            dismiss()
        } catch RemoteClient.ClientError.timeout {
            failure = "O PC não respondeu em 30 segundos."
        } catch RemoteClient.ClientError.refused(let why) {
            failure = "O PC recusou: \(why)"
        } catch {
            failure = "Não consegui falar com o PC."
        }
    }
}
