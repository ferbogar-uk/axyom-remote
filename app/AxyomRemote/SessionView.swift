import SwiftUI
import AxyomRemoteCore

/// Conversation of one session: read, reply (text or voice), approve or deny
/// tool permissions, answer the agent's questions, approve or reject plans,
/// and stop. Every button sends the same messages the desktop already handles;
/// none of it is decoration. New messages are fetched every few seconds.
struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    let sessionId: String

    @State private var allItems: [TranscriptItem] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var busyId: String?
    @State private var actionError: String?
    @State private var notice: String?
    @State private var draft = ""
    @State private var choices: [String: [String: Set<String>]] = [:]   // questionId -> question -> labels
    @State private var planFeedback: [String: String] = [:]
    @State private var conversation = false
    @StateObject private var listener = SpeechListener()
    @StateObject private var voice = ReplySpeaker()
    @FocusState private var typing: Bool

    private var session: FleetSession? { model.snapshot.sessions.first { $0.id == sessionId } }
    private var visible: [TranscriptItem] {
        allItems.filter { !$0.hidden && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var online: Bool { model.pcStatus.isOnline }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if loading && allItems.isEmpty { ProgressView().tint(Theme.amber).frame(maxWidth: .infinity).padding(.top, 40) }
                    if let failure { Text(failure).font(.subheadline).foregroundStyle(Theme.danger).card() }
                    ForEach(visible) { item in bubble(item) }
                    if !loading && visible.isEmpty && failure == nil {
                        Text("Esta sessão ainda não tem mensagens legíveis.").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    if session?.isExecuting == true {
                        HStack(spacing: 8) { ProgressView().tint(Theme.green); Text("O agente está a trabalhar…").font(.footnote).foregroundStyle(Theme.muted) }
                    }
                    ForEach(PendingPrompts.permissions(in: allItems)) { permissionCard($0) }
                    ForEach(PendingPrompts.questions(in: allItems)) { questionCard($0) }
                    ForEach(PendingPrompts.plans(in: allItems)) { planCard($0) }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.green) }
                    if let actionError { Text(actionError).font(.subheadline).foregroundStyle(Theme.danger).card() }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: allItems.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .background(Theme.background)
        .navigationTitle(session?.title ?? "Sessão")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    conversation.toggle()
                    if !conversation { voice.stop() }
                } label: {
                    Image(systemName: conversation ? "waveform.circle.fill" : "waveform.circle")
                        .foregroundStyle(conversation ? Theme.amber : Theme.text)
                }
                .accessibilityLabel(conversation ? "Desligar conversa por voz" : "Ligar conversa por voz")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Parar") { Task { await stop() } }
                    .tint(Theme.danger)
                    .disabled(!online || busyId != nil)
            }
        }
        .task { await fullLoad() }
        .task(id: sessionId) { await poll() }
        .refreshable { await fullLoad() }
        .onChange(of: listener.listening) { was, now in
            guard was, !now else { return }
            let heard = listener.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heard.isEmpty else { return }
            if conversation { Task { await send(heard, source: "voice") } } else { draft = heard }
        }
        .onDisappear { listener.stop(); voice.stop() }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if conversation {
                Text(listener.listening ? "A ouvir… paro sozinho quando te calares." : "Conversa por voz ligada: falas, envio sozinho e leio a resposta em voz alta.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let problem = listener.problem { Text(problem).font(.caption).foregroundStyle(Theme.danger) }
            if listener.listening && !listener.transcript.isEmpty {
                Text("“\(listener.transcript)”").font(.footnote).foregroundStyle(Theme.textSoft).lineLimit(3)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Responder ao agente…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($typing)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
                Button {
                    voice.stop()
                    listener.toggle(autoStop: conversation)
                } label: {
                    Image(systemName: listener.listening ? "stop.fill" : "mic.fill")
                        .font(.title3).frame(width: 48, height: 48)
                        .foregroundStyle(listener.listening ? Theme.onAmber : Theme.text)
                        .background(listener.listening ? Theme.amber : Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.borderStrong, lineWidth: listener.listening ? 0 : 1))
                }
                .accessibilityLabel(listener.listening ? "Parar de ouvir" : "Falar")
                Button {
                    let text = draft
                    Task { await send(text, source: "keyboard") }
                } label: {
                    Image(systemName: "arrow.up").font(.title3.weight(.semibold)).frame(width: 48, height: 48)
                        .foregroundStyle(canSend ? Theme.onAmber : Theme.muted)
                        .background(canSend ? Theme.amber : Theme.border, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Enviar")
            }
            if !online { Text("O PC está offline: a resposta fica guardada e corre quando ele ligar.").font(.caption).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.background)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && busyId == nil && model.snapshot.connected
    }

    @ViewBuilder private func bubble(_ item: TranscriptItem) -> some View {
        let mine = item.direction == "input"
        Text(item.text)
            .font(.body).foregroundStyle(mine ? Theme.text : Theme.textSoft)
            .textSelection(.enabled)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(mine ? Theme.amberFill : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(mine ? Theme.amberBorder : .clear, lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    // MARK: Prompt cards

    @ViewBuilder private func permissionCard(_ p: PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("O agente pede permissão").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.amberLight)
            if !p.toolName.isEmpty { Text(p.toolName).font(.footnote).foregroundStyle(Theme.muted) }
            Text(p.rawCommand.isEmpty ? p.patternDisplayName : p.rawCommand)
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.text)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if p.isDestructive { Text("Atenção: esta ação pode ser destrutiva.").font(.footnote).foregroundStyle(Theme.danger) }
            ForEach(p.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.muted) }
            HStack(spacing: 10) {
                Button("Recusar") { act(p.id) { try await $0.respondToPermission(sessionId: sessionId, promptId: p.id, allow: false, targetDeviceId: target) } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Aprovar uma vez") { act(p.id) { try await $0.respondToPermission(sessionId: sessionId, promptId: p.id, allow: true, targetDeviceId: target) } }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .disabled(busyId != nil || !online)
        }
        .card(fill: Theme.amberSurface, stroke: Theme.amberBorder)
    }

    @ViewBuilder private func questionCard(_ q: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("O agente pergunta").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.amberLight)
            ForEach(q.questions, id: \.self) { item in
                VStack(alignment: .leading, spacing: 8) {
                    if !item.header.isEmpty { Text(item.header).sectionLabel() }
                    Text(item.question).font(.body).foregroundStyle(Theme.text)
                    ForEach(item.options, id: \.self) { option in
                        optionRow(q.id, item, option)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Ignorar") { act(q.id) { try await $0.answerQuestion(sessionId: sessionId, questionId: q.id, answers: [:], cancelled: true, targetDeviceId: target) } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Responder") {
                    let answers = answerMap(q)
                    act(q.id) { try await $0.answerQuestion(sessionId: sessionId, questionId: q.id, answers: answers, targetDeviceId: target) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(answerMap(q).count < q.questions.count)
            }
            .disabled(busyId != nil || !online)
        }
        .card(fill: Theme.amberSurface, stroke: Theme.amberBorder)
    }

    @ViewBuilder private func optionRow(_ id: String, _ item: PendingQuestion.Question, _ option: PendingQuestion.Option) -> some View {
        let on = choices[id]?[item.question]?.contains(option.label) ?? false
        let icon = on ? (item.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle") : (item.multiSelect ? "square" : "circle")
        Button { toggle(id, item, option.label) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(on ? Theme.amber : Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.body).foregroundStyle(Theme.text)
                    if !option.description.isEmpty { Text(option.description).font(.footnote).foregroundStyle(Theme.muted) }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(minHeight: 44)
            .background(on ? Theme.amberFill : Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func planCard(_ plan: PendingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("O agente quer aprovação do plano").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.amberLight)
            if !plan.summary.isEmpty {
                Text(plan.summary).font(.footnote).foregroundStyle(Theme.text)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let path = plan.filePath { Text(path).font(.caption).foregroundStyle(Theme.muted) }
            TextField("Se recusares, diz o que mudar (opcional)", text: feedbackBinding(plan.id), axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(Theme.text)
                .padding(10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                Button("Recusar") {
                    let feedback = planFeedback[plan.id]
                    act(plan.id) { try await $0.respondToPlan(sessionId: sessionId, promptId: plan.id, approved: false, feedback: feedback, targetDeviceId: target) }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Aprovar plano") { act(plan.id) { try await $0.respondToPlan(sessionId: sessionId, promptId: plan.id, approved: true, targetDeviceId: target) } }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .disabled(busyId != nil || !online)
        }
        .card(fill: Theme.amberSurface, stroke: Theme.amberBorder)
    }

    private func feedbackBinding(_ id: String) -> Binding<String> {
        Binding(get: { planFeedback[id] ?? "" }, set: { planFeedback[id] = $0 })
    }

    private func toggle(_ id: String, _ q: PendingQuestion.Question, _ label: String) {
        var forQ = choices[id] ?? [:]
        var set = forQ[q.question] ?? []
        if q.multiSelect {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = [label]
        }
        forQ[q.question] = set
        choices[id] = forQ
    }

    /// Question text -> chosen label(s). Several labels are joined with ", ".
    private func answerMap(_ q: PendingQuestion) -> [String: String] {
        var out: [String: String] = [:]
        for item in q.questions {
            let chosen = choices[q.id]?[item.question] ?? []
            let picked = item.options.map(\.label).filter { chosen.contains($0) }
            if !picked.isEmpty { out[item.question] = picked.joined(separator: ", ") }
        }
        return out
    }

    // MARK: Actions

    private var target: String? { session?.hostDeviceId ?? model.desktopDeviceId }

    private func act(_ id: String, _ work: @escaping (RemoteClient) async throws -> Void) {
        guard let client = model.client else { return }
        Task {
            busyId = id
            do {
                try await work(client)
                actionError = nil
                notice = "Enviado ao PC."
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await fullLoad()
            } catch {
                actionError = "Não consegui enviar ao PC. Confirma que o PC está ligado e tenta outra vez."
            }
            busyId = nil
        }
    }

    private func send(_ text: String, source: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = model.client, !trimmed.isEmpty else { return }
        busyId = "send"
        defer { busyId = nil }
        do {
            try await client.sendPrompt(sessionId: sessionId, text: trimmed, source: source, targetDeviceId: target)
            draft = ""
            actionError = nil
            notice = online ? "Resposta enviada. À espera do agente…" : "Resposta guardada. Corre quando o PC ligar."
            typing = false
        } catch RemoteClient.ClientError.notConnected {
            actionError = "Sem ligação ao servidor. A tua resposta não foi enviada."
        } catch {
            actionError = "Não consegui enviar a resposta. Tenta outra vez."
        }
    }

    private func stop() async {
        guard let client = model.client else { return }
        busyId = "stop"
        do {
            try await client.cancel(sessionId: sessionId, targetDeviceId: target)
            actionError = nil
            notice = "Pedido de paragem enviado."
        } catch {
            actionError = "Não consegui enviar o pedido de paragem ao PC. Confirma que o PC está ligado."
        }
        busyId = nil
    }

    // MARK: Loading

    private func fullLoad() async {
        guard let client = model.client else { return }
        do {
            allItems = try await client.loadTranscript(sessionId: sessionId)
            failure = nil
        } catch {
            if allItems.isEmpty { failure = "Não consegui ler esta sessão. Puxa para baixo para tentar outra vez." }
        }
        loading = false
    }

    /// Fetch only rows after the last one we have, every 4 seconds while the screen is open.
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, !loading, let client = model.client else { continue }
            let last = allItems.map(\.sequence).max()
            guard let fresh = try? await client.loadTranscript(sessionId: sessionId, afterSequence: last) else { continue }
            let known = Set(allItems.map(\.id))
            let added = fresh.filter { !known.contains($0.id) }
            guard !added.isEmpty else { continue }
            allItems.append(contentsOf: added)
            if added.contains(where: { $0.direction == "output" }) { notice = nil }
            if conversation { voice.speak(SpokenReply.lines(from: added)) }
        }
    }
}
