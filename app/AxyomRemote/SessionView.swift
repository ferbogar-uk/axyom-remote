import SwiftUI
import PhotosUI
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
    @State private var phase: ConversationPhase = .idle
    @State private var lastReply: String?
    @State private var waitStarted = Date()
    @StateObject private var listener = SpeechListener()
    @StateObject private var voice = ReplySpeaker()
    @FocusState private var typing: Bool
    @State private var images: [PromptImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var commitFiles: [String: Set<String>] = [:]     // proposalId -> files left ticked
    @State private var commitMessages: [String: String] = [:]

    private var session: FleetSession? { model.snapshot.sessions.first { $0.id == sessionId } }
    private var visible: [ChatLine] { ChatLines.build(allItems, provider: session?.provider ?? "") }
    private var online: Bool { model.pcStatus.isOnline }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                    ForEach(PendingPrompts.commits(in: allItems)) { commitCard($0) }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.green) }
                    if let actionError { Text(actionError).font(.subheadline).foregroundStyle(Theme.danger).card() }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: allItems.count) { _, _ in
                DispatchQueue.main.async { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .background(Theme.background)
        .navigationTitle(session?.title ?? "Sessão")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if let provider = session?.provider { AgentBadge(provider: provider, size: 22) }
                    Text(session?.title ?? "Sessão").font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if conversation { endConversation() } else { startConversation() }
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
        .task(id: sessionId) { await live() }
        .task(id: sessionId) { await poll() }
        .refreshable { await fullLoad() }
        .onChange(of: listener.listening) { was, now in
            guard was, !now else { return }
            let heard = listener.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if conversation {
                guard !heard.isEmpty else { phase = .idle; return }
                phase = .waiting
                waitStarted = Date()
                Task { await send(heard, source: "voice") }
            } else if !heard.isEmpty {
                draft = heard
            }
        }
        // Reply finished being read aloud: open the microphone again.
        .onChange(of: voice.speaking) { was, now in
            guard was, !now, conversation, phase == .speaking else { return }
            listenAgain()
        }
        // Agent finished but said nothing readable (only tools): don't hang in "waiting".
        .onChange(of: session?.isExecuting ?? false) { was, now in
            guard was, !now, conversation, phase == .waiting else { return }
            Task {
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                if conversation, phase == .waiting { listenAgain() }
            }
        }
        .overlay {
            if conversation {
                ConversationPanel(
                    phase: phase,
                    heard: listener.transcript,
                    lastReply: lastReply,
                    problem: listener.problem ?? actionError,
                    onTapMain: tapMain,
                    onEnd: endConversation)
                .transition(.opacity)
            }
        }
        .onDisappear { listener.stop(); voice.stop() }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 4, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for (index, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data),
                       let img = ImageShrink.prompt(from: ui, name: "foto-\(images.count + index + 1).jpg") {
                        images.append(img)
                    }
                }
                photoItems = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { ui in
                if let img = ImageShrink.prompt(from: ui, name: "camara-\(images.count + 1).jpg") { images.append(img) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Conversation loop

    private func startConversation() {
        typing = false
        voice.stop()
        conversation = true
        listenAgain()
    }

    private func endConversation() {
        conversation = false
        phase = .idle
        listener.stop()
        voice.stop()
    }

    private func listenAgain() {
        guard conversation else { return }
        phase = .listening
        if !listener.listening { listener.toggle(autoStop: true) }
    }

    /// Main circle: send now while listening, interrupt while speaking, talk when idle.
    private func tapMain() {
        switch phase {
        case .listening: listener.stop()
        case .speaking: voice.stop(); listenAgain()
        case .idle: listenAgain()
        case .waiting: break
        }
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
            AttachmentTray(images: $images)
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { showPhotos = true } label: { Label("Escolher fotografias", systemImage: "photo.on.rectangle") }
                    Button { showCamera = true } label: { Label("Tirar foto", systemImage: "camera") }
                } label: {
                    Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 44, height: 48)
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel("Anexar imagem")
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
                    Task { await send(text, source: "keyboard", images: images) }
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
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty) && busyId == nil && model.snapshot.connected
    }

    @ViewBuilder private func bubble(_ item: ChatLine) -> some View {
        let mine = item.mine
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

    @ViewBuilder private func commitCard(_ c: PendingCommit) -> some View {
        let ticked = commitFiles[c.id] ?? Set(c.files)
        VStack(alignment: .leading, spacing: 10) {
            Text("O agente propõe um commit").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.amberLight)
            if !c.reasoning.isEmpty { Text(c.reasoning).font(.footnote).foregroundStyle(Theme.muted) }
            ForEach(c.files, id: \.self) { file in
                let on = ticked.contains(file)
                Button {
                    var set = ticked
                    if on { set.remove(file) } else { set.insert(file) }
                    commitFiles[c.id] = set
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Theme.amber : Theme.muted)
                        Text(file).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.text).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
            }
            TextField("Mensagem do commit", text: Binding(get: { commitMessages[c.id] ?? c.message }, set: { commitMessages[c.id] = $0 }), axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                Button("Cancelar") {
                    act(c.id) { try await $0.respondToCommit(sessionId: sessionId, proposalId: c.id, commit: false, files: [], message: "", targetDeviceId: target) }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Fazer commit") {
                    let files = c.files.filter { ticked.contains($0) }
                    let message = (commitMessages[c.id] ?? c.message).trimmingCharacters(in: .whitespacesAndNewlines)
                    act(c.id) { try await $0.respondToCommit(sessionId: sessionId, proposalId: c.id, commit: true, files: files, message: message, targetDeviceId: target) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(ticked.isEmpty || (commitMessages[c.id] ?? c.message).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var target: String? { session?.hostDeviceId ?? model.desktopId(forEncryptedProjectId: session?.encryptedProjectId) }

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

    private func send(_ text: String, source: String, images: [PromptImage] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = model.client, !trimmed.isEmpty || !images.isEmpty else { return }
        busyId = "send"
        defer { busyId = nil }
        do {
            try await client.sendPrompt(sessionId: sessionId, text: trimmed, images: images, source: source, targetDeviceId: target)
            draft = ""
            if !images.isEmpty { self.images = [] }
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

    /// Live: keep the session room open; new rows arrive the moment the PC writes
    /// them (no 4-second wait, no new connection per check). Reconnects with a
    /// short backoff if the connection drops.
    private func live() async {
        var delay: UInt64 = 1
        while !Task.isCancelled {
            guard let client = model.client, !loading else {
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }
            do {
                for try await batch in client.liveTranscript(sessionId: sessionId, afterSequence: allItems.map(\.sequence).max()) {
                    merge(batch)
                    delay = 1
                }
            } catch {}
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 15)
        }
    }

    /// Safety net in case live updates stop arriving: a slow check every 15 s.
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, !loading, let client = model.client else { continue }
            let last = allItems.map(\.sequence).max()
            guard let fresh = try? await client.loadTranscript(sessionId: sessionId, afterSequence: last) else { continue }
            merge(fresh)
        }
    }

    /// Add new rows; in conversation mode, read aloud the agent text they complete.
    private func merge(_ fresh: [TranscriptItem]) {
        let known = Set(allItems.map(\.id))
        let added = fresh.filter { !known.contains($0.id) }
        guard !added.isEmpty else { return }
        // Build the chat from ALL rows before and after: a reply's text is often
        // split across rows (deltas + completion), so building from only the new
        // rows found nothing to say and the reply was never read aloud.
        let provider = session?.provider ?? ""
        let before = ChatLines.build(allItems, provider: provider).filter { !$0.mine }.map(\.text)
        allItems.append(contentsOf: added)
        allItems.sort { $0.sequence < $1.sequence }
        if added.contains(where: { $0.direction == "output" }) { notice = nil }
        if conversation {
            let after = ChatLines.build(allItems, provider: provider).filter { !$0.mine }.map(\.text)
            let spoken = Array(after.dropFirst(before.count))
            if !spoken.isEmpty {
                if listener.listening { listener.stop() }
                lastReply = spoken.last
                phase = .speaking
                voice.speak(spoken.map { $0.count > 600 ? String($0.prefix(600)) + "…" : $0 })
            }
        }
    }
}
