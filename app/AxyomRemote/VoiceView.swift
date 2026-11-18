import SwiftUI
import AxyomRemoteCore

/// Voice command with confirmation: new session, reply, approve, deny and
/// status. Nothing is sent until the user confirms. Reply, approve and deny go
/// to the session that is waiting for you (or the most recent one), shown on screen first.
struct VoiceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var listener = SpeechListener()
    @State private var sending = false
    @State private var failure: String?
    @State private var done: String?
    @StateObject private var speaker = ReplySpeaker()

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
            Text(listener.onDevice ? "Nada é enviado ao PC até confirmares. O reconhecimento de voz corre no iPhone." : "Nada é enviado ao PC até confirmares. O reconhecimento de voz usa os servidores da Apple (o português não está transferido neste iPhone).")
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
        case .reply(let prompt):
            actionCard(title: "Responder", detail: prompt, confirm: "Confirmar e enviar") { s in { client in
                try await client.sendPrompt(sessionId: s.id, text: prompt, source: "voice", targetDeviceId: s.hostDeviceId ?? model.desktopId(forEncryptedProjectId: s.encryptedProjectId))
                return "Resposta enviada para \"\(s.title)\"."
            } }
        case .approve:
            actionCard(title: "Aprovar", detail: "O primeiro pedido de permissão ou plano à espera nesta sessão.", confirm: "Confirmar e aprovar") { s in { client in
                try await decide(s, allow: true, client: client)
            } }
        case .deny:
            actionCard(title: "Recusar", detail: "O primeiro pedido de permissão ou plano à espera nesta sessão.", confirm: "Confirmar e recusar") { s in { client in
                try await decide(s, allow: false, client: client)
            } }
        case .status:
            Text("À espera de ti: \(board.waiting.count). A trabalhar: \(board.working.count).")
                .font(.subheadline).foregroundStyle(Theme.textSoft).card()
        case .empty:
            Text("Não percebi nada. Tenta outra vez.").font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    /// The session a reply/approve/deny goes to: the one waiting for you, else the latest working one, else the latest.
    private var targetSession: FleetSession? {
        board.waiting.first ?? board.working.first ?? board.recent.first
    }

    @ViewBuilder private func actionCard(title: String, detail: String, confirm: String,
                                         run: @escaping (FleetSession) -> ((RemoteClient) async throws -> String)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entendi isto").sectionLabel(Theme.amber)
            fact("Ação", title)
            fact("Sessão", targetSession.map { "\($0.title) · \($0.projectName)" } ?? "Nenhuma sessão encontrada.")
            fact("Detalhe", detail)
            if let done { Text(done).font(.subheadline).foregroundStyle(Theme.green) }
            HStack(spacing: 8) {
                Button(sending ? "A enviar…" : confirm) {
                    if let s = targetSession { Task { await perform(run(s)) } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(targetSession == nil || sending || !model.snapshot.connected)
                Button("Cancelar") { listener.transcript = "" }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 110)
            }
        }
        .card(fill: Theme.amberSurface, stroke: Theme.amberBorder)
    }

    private func perform(_ work: (RemoteClient) async throws -> String) async {
        guard let client = model.client else { return }
        sending = true; failure = nil
        defer { sending = false }
        do {
            done = try await work(client)
            speaker.speak([done ?? ""])
        } catch RemoteClient.ClientError.refused(let why) {
            failure = why
        } catch {
            failure = "Não consegui falar com o PC."
        }
    }

    /// Answer the first pending permission; if there is none, the first pending plan.
    private func decide(_ s: FleetSession, allow: Bool, client: RemoteClient) async throws -> String {
        let items = try await client.loadTranscript(sessionId: s.id)
        let target = s.hostDeviceId ?? model.desktopId(forEncryptedProjectId: s.encryptedProjectId)
        if let p = PendingPrompts.permissions(in: items).first {
            try await client.respondToPermission(sessionId: s.id, promptId: p.id, allow: allow, targetDeviceId: target)
            return allow ? "Aprovado uma vez: \(p.rawCommand.isEmpty ? p.patternDisplayName : p.rawCommand)." : "Recusado: \(p.rawCommand.isEmpty ? p.patternDisplayName : p.rawCommand)."
        }
        if let plan = PendingPrompts.plans(in: items).first {
            try await client.respondToPlan(sessionId: s.id, promptId: plan.id, approved: allow, targetDeviceId: target)
            return allow ? "Plano aprovado." : "Plano recusado."
        }
        if !PendingPrompts.questions(in: items).isEmpty {
            throw RemoteClient.ClientError.refused("Esta sessão faz uma pergunta com opções. Abre a sessão para escolher.")
        }
        throw RemoteClient.ClientError.refused("Não há nada à espera de aprovação nesta sessão.")
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
            let encrypted = board.projects.first(where: { $0.id == project })?.encryptedId
            _ = try await client.createSession(projectId: project, provider: agent.providerId, prompt: prompt, targetDeviceId: model.desktopId(forEncryptedProjectId: encrypted))
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
