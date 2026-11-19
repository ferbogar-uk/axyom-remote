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
    /// Open straight into the hands-free voice conversation (home voice button).
    var startTalking = false

    @State private var allItems: [TranscriptItem] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var busyId: String?
    @State private var actionError: String?
    @State private var notice: String?
    @State private var draft = ""
    @State private var choices: [String: [String: Set<String>]] = [:]   // questionId -> question -> labels
    @State private var planFeedback: [String: String] = [:]
    @State private var contentUnderBar = false
    @State private var conversation = false
    @State private var phase: ConversationPhase = .idle
    @State private var lastReply: String?
    @State private var waitStarted = Date()
    @StateObject private var listener = SpeechListener()
    @StateObject private var voice = ReplySpeaker()
    @FocusState private var typing: Bool
    @State private var images: [PromptImage] = []
    @State private var localQueued: [QueuedPreview] = []
    @State private var removedQueued: Set<String> = []
    @State private var pendingModel: String?
    @State private var expandedSteps: Set<String> = []
    @State private var atBottom = true
    @State private var unseen = 0
    @State private var viewportHeight: CGFloat = 800
    @State private var searching = false
    @State private var query = ""
    @State private var matchIndex = 0
    @State private var scrollTarget: String?
    @FocusState private var searchFocused: Bool
    @State private var lastSharedDraft: String?
    @State private var draftTask: Task<Void, Never>?
    @State private var showInfo = false
    @State private var pendingEffort: String?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var commitFiles: [String: Set<String>] = [:]     // proposalId -> files left ticked
    @State private var commitMessages: [String: String] = [:]

    private var session: FleetSession? { model.snapshot.sessions.first { $0.id == sessionId } }
    private var visible: [ChatLine] { ChatLines.build(allItems, provider: session?.provider ?? "", includeSteps: true) }

    /// Messages, with runs of consecutive tool steps folded into one group.
    private enum Row: Identifiable {
        case message(ChatLine)
        case steps([ChatLine])
        var id: String {
            switch self {
            case .message(let l): return l.id
            case .steps(let s): return "steps-" + (s.first?.id ?? "")
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        for line in visible {
            if line.isStep, case .steps(var run)? = out.last {
                run.append(line)
                out[out.count - 1] = .steps(run)
            } else {
                out.append(line.isStep ? .steps([line]) : .message(line))
            }
        }
        return out
    }
    private var online: Bool { model.pcStatus.isOnline }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if loading && allItems.isEmpty { ProgressView().tint(Theme.amber).frame(maxWidth: .infinity).padding(.top, 40) }
                    if !model.snapshot.connected {
                        OfflineBanner(message: model.snapshot.lastError)
                    } else if let failure {
                        Text(failure).font(.subheadline).foregroundStyle(Theme.danger).card()
                    }
                    ForEach(rows) { row in
                        switch row {
                        case .message(let item):
                            bubble(item)
                                .id(item.id)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.accent, lineWidth: isCurrentMatch(item.id) ? 2 : 0).padding(-4))
                        case .steps(let steps): stepsRow(steps)
                        }
                    }
                    if !loading && visible.isEmpty && failure == nil {
                        Text("Esta sessão ainda não tem mensagens legíveis.").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    if session?.isExecuting == true {
                        WorkingLine(label: AgentActivity.current(allItems))
                    }
                    ForEach(PendingPrompts.permissions(in: allItems)) { permissionCard($0) }
                    ForEach(PendingPrompts.questions(in: allItems)) { questionCard($0) }
                    ForEach(PendingPrompts.plans(in: allItems)) { planCard($0) }
                    ForEach(PendingPrompts.commits(in: allItems)) { commitCard($0) }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.green) }
                    if let actionError { Text(actionError).font(.subheadline).foregroundStyle(Theme.danger).card() }
                    Color.clear.frame(height: 1).id("end")
                        .background(GeometryReader { g in
                            Color.clear.preference(key: EndOffsetKey.self, value: g.frame(in: .named("chat")).minY)
                        })
                }
                .padding(16)
            }
            .coordinateSpace(.named("chat"))
            .background(GeometryReader { g in Color.clear.onAppear { viewportHeight = g.size.height }
                .onChange(of: g.size.height) { _, h in viewportHeight = h } })
            .onPreferenceChange(EndOffsetKey.self) { y in
                let bottom = y <= viewportHeight + 60
                if bottom != atBottom { atBottom = bottom }
                if bottom { unseen = 0 }
            }
            .scrollDismissesKeyboard(.interactively)
            .contentBehindBar($contentUnderBar)
            .onChange(of: allItems.count) { old, new in
                // Follow new messages only when you are already at the end; otherwise count them.
                if atBottom || old == 0 {
                    DispatchQueue.main.async { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                } else {
                    unseen += max(0, new - old)
                }
            }
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay(alignment: .bottom) {
                if !atBottom && !allItems.isEmpty {
                    Button {
                        withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                        unseen = 0
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                            if unseen > 0 { Text("\(unseen) nova\(unseen == 1 ? "" : "s")") }
                        }
                        .font(.footnote.weight(.bold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 14).frame(minWidth: 40, minHeight: 40)
                        .background(Theme.barGlass.opacity(0.9), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                    }
                    .padding(.bottom, 8)
                    .accessibilityLabel(unseen > 0 ? "Ir para o fim, \(unseen) mensagens novas" : "Ir para o fim")
                }
            }
        }
        .safeAreaInset(edge: .top) { if searching { searchBar } }
        .onChange(of: draft) { _, text in shareDraftSoon(text) }
        .onChange(of: session?.draftUpdatedAt) { _, _ in
            // A draft typed on the PC shows up here only if the box is empty.
            if draft.isEmpty, let shared = session?.draftInput, !shared.isEmpty, shared != lastSharedDraft {
                draft = shared
                lastSharedDraft = shared
            }
        }
        .sheet(isPresented: $showInfo) { SessionInfoSheet(sessionId: sessionId, modelName: chosenModel?.name ?? modelLabel).environmentObject(model) }
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
                Button { Task { await stop() } } label: {
                    Image(systemName: "stop.circle").foregroundStyle(session?.isExecuting == true ? Theme.danger : Theme.muted)
                }
                .disabled(!online || busyId != nil || session?.isExecuting != true)
                .accessibilityLabel("Parar o agente")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { searching = true; searchFocused = true } label: { Label("Procurar na conversa", systemImage: "magnifyingglass") }
                    Button { showInfo = true } label: { Label("Informação da sessão", systemImage: "info.circle") }
                    Button { Task { await fullLoad() } } label: { Label("Atualizar conversa", systemImage: "arrow.clockwise") }
                    Button { startConversation() } label: { Label("Conversa por voz", systemImage: "waveform") }
                    Button(role: .destructive) { Task { await stop() } } label: { Label("Parar o agente", systemImage: "stop.circle") }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.text).frame(width: 32, height: 32)
                }
                .accessibilityLabel("Mais opções")
            }
        }
        .task {
            if allItems.isEmpty {
                let cached = model.cache.loadTranscript(sessionId: sessionId)
                if !cached.isEmpty { allItems = cached; loading = false }
            }
            if startTalking && !conversation { startConversation() }
            if draft.isEmpty, let shared = session?.draftInput, !shared.isEmpty {
                draft = shared
                lastSharedDraft = shared
            }
            await fullLoad()
            try? await model.client?.markRead(sessionId: sessionId)
        }
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
                let current = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = current.isEmpty ? heard : current + " " + heard
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
        listener.stop(discard: true)
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

    /// Floating composer, like the Claude app: text on top; attach, model, dictate
    /// and the orange action at the bottom. The orange button starts a voice
    /// conversation while the box is empty and becomes "send" once you type.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem = listener.problem { Text(problem).font(.caption).foregroundStyle(Theme.danger).padding(.horizontal, 8) }
            if !online { Text("O PC está offline: a resposta fica guardada e corre quando ele ligar.").font(.caption).foregroundStyle(Theme.muted).padding(.horizontal, 8) }
            queueTray
            if conversation && phase == .waiting {
                ThinkingDots().padding(.horizontal, 12).padding(.bottom, 2)
            }
            VStack(alignment: .leading, spacing: 10) {
                AttachmentTray(images: $images)
                if listener.listening && !conversation {
                    Text(listener.transcribing ? "A transcrever…" : listener.transcript.isEmpty ? "A ouvir…" : "“\(listener.transcript)”")
                        .font(.body).foregroundStyle(Theme.textSoft).lineLimit(4)
                }
                if conversation {
                    // Conversation: what you say, in italics, in place of the text field (like Claude's voice mode).
                    Text(phase == .listening && !listener.transcript.isEmpty ? listener.transcript : " ")
                        .font(.body.italic()).foregroundStyle(Theme.text).lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .padding(.horizontal, 4)
                        .accessibilityLabel(listener.transcript.isEmpty ? "Conversa por voz" : listener.transcript)
                } else {
                    TextField("", text: $draft, prompt: Text("Responder ao agente…").foregroundStyle(Theme.textSoft), axis: .vertical)
                        .lineLimit(1...6)
                        .focused($typing)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 4)
                }
                HStack(spacing: 10) {
                    Menu {
                        Button { showPhotos = true } label: { Label("Escolher fotografias", systemImage: "photo.on.rectangle") }
                        Button { showCamera = true } label: { Label("Tirar foto", systemImage: "camera") }
                    } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                            .frame(width: 40, height: 40).background(Theme.text.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Anexar imagem")
                    modelChip
                    Spacer(minLength: 0)
                    Button {
                        if conversation { endConversation(); return }
                        voice.stop()
                        listener.toggle(autoStop: false)
                    } label: {
                        Image(systemName: conversation ? "xmark" : listener.listening ? "stop.fill" : "mic")
                            .font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                            .frame(width: 40, height: 40).background(Theme.text.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(conversation ? "Terminar conversa por voz" : listener.listening ? "Parar o ditado" : "Ditar")
                    actionButton
                }
            }
            .padding(14)
            .glassBar(RoundedRectangle(cornerRadius: 26, style: .continuous))
            // Dark surround: bar top to screen bottom, a little inside the bar.
            .background(alignment: .bottom) {
                // Layers behind the glass, back to front: dark surround, then the voice light.
                ZStack(alignment: .bottom) {
                    FrostedBackdrop(cornerRadius: 26, active: contentUnderBar)
                    if voiceGlowing {
                        ScreenGlow(color: phase == .listening ? Theme.voiceBlue : Theme.accent,
                                   level: phase == .listening ? listener.level : nil)
                            .padding(.horizontal, -12)
                            .frame(height: 440)
                            .offset(y: 66)        // down through the home-indicator area to the screen edge
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: voiceGlowing)
            }
            .onChange(of: phase) { old, new in phaseHaptic(old, new) }
            .overlay {
                if conversation && phase == .listening {
                    VoiceGlow(color: Theme.voiceBlue, level: listener.level)
                } else if conversation && phase == .speaking {
                    VoiceGlow(color: Theme.accent, level: nil)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: phase)
        }
        .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 6)
    }

    /// Light tap when the app starts listening and when the agent's reply arrives.
    private func phaseHaptic(_ old: ConversationPhase, _ new: ConversationPhase) {
        if new == .listening && old != .listening { Prefs.tap() }
        if new == .speaking && old == .waiting { Prefs.tap() }
    }

    private var voiceGlowing: Bool { conversation && (phase == .listening || phase == .speaking) }

    private var hasContent: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    /// Orange: waveform (start voice conversation) when empty, arrow (send) when there is something to send.
    /// In a voice conversation the orange button follows the phase:
    /// listening → send now, speaking → interrupt, thinking → wait, idle → talk.
    @ViewBuilder private var actionButton: some View {
        if conversation && !hasContent {
            let icon = switch phase {
            case .listening: "arrow.up"
            case .speaking: "stop.fill"
            case .waiting: "ellipsis"
            case .idle: "waveform"
            }
            Button(action: tapMain) {
                Image(systemName: icon)
                    .font(.body.weight(.bold)).foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44).background(Theme.accent, in: Circle())
                    .opacity(phase == .waiting ? 0.45 : 1)
            }
            .disabled(phase == .waiting)
            .accessibilityLabel(phase == .listening ? "Enviar já" : phase == .speaking ? "Interromper" : phase == .waiting ? "À espera do agente" : "Falar")
        } else {
            sendButton
        }
    }

    private var sendButton: some View {
        Button {
            if hasContent {
                let text = draft
                Task { await send(text, source: "keyboard", images: images) }
            } else {
                startConversation()
            }
        } label: {
            Image(systemName: hasContent ? "arrow.up" : "waveform")
                .font(.body.weight(.bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44).background(Theme.accent, in: Circle())
                .opacity(hasContent && !canSend ? 0.45 : 1)
        }
        .disabled(hasContent ? !canSend : !model.snapshot.connected)
        .accessibilityLabel(hasContent ? (busy ? "Pôr na fila" : "Enviar") : "Começar conversa por voz")
        .contextMenu {
            // While the agent works, a tap queues; hold for "send now" (like Claude).
            if hasContent && busy {
                Button { let text = draft; Task { await send(text, source: "keyboard", images: images) } } label: {
                    Label("Pôr na fila", systemImage: "text.append")
                }
                Button { let text = draft; Task { await send(text, source: "keyboard", images: images, now: true) } } label: {
                    Label("Enviar agora", systemImage: "arrow.uturn.forward")
                }
            }
        }
    }

    /// The agent is in the middle of a turn: new messages wait in the queue.
    private var busy: Bool { session?.isExecuting == true }

    /// Exact model from the transcript (e.g. "Opus 5.5"), else the index's family name.
    private var modelLabel: String {
        ModelInfo.display(ModelInfo.latest(in: allItems)) ?? ModelName.display(session?.model, provider: session?.provider)
    }

    private var desktopModels: [PlanUsage.ModelChoice] { model.snapshot.planUsage.first(where: { !$0.models.isEmpty })?.models ?? [] }
    private var modelChoices: [PlanUsage.ModelChoice] { ModelPicker.choices(for: session?.provider ?? "", in: desktopModels) }
    private var chosenModelId: String? { pendingModel ?? session?.model }
    private var chosenModel: PlanUsage.ModelChoice? { ModelPicker.current(chosenModelId, in: desktopModels) }
    private var chosenEffort: String? {
        pendingEffort ?? session?.effortLevel ?? model.snapshot.planUsage.first?.defaultEffort
    }

    /// What to send with the next message: only what you changed.
    private var promptOptions: PromptOptions {
        PromptOptions(model: pendingModel.flatMap { $0 == session?.model ? nil : $0 },
                      effortLevel: pendingEffort.flatMap { $0 == session?.effortLevel ? nil : $0 })
    }

    /// Model and effort picker, filled from the list the PC publishes. The choice
    /// travels with your next message and the PC applies it before running it.
    private var modelChip: some View {
        Menu {
            if modelChoices.isEmpty {
                Text("O PC ainda não enviou a lista de modelos.")
            } else {
                Section("Modelo") {
                    ForEach(modelChoices) { m in
                        Button {
                            pendingModel = m.id
                            if let e = pendingEffort ?? session?.effortLevel, !m.efforts.contains(e) { pendingEffort = nil }
                        } label: {
                            if m.id == chosenModelId { Label(m.name, systemImage: "checkmark") } else { Text(m.name) }
                        }
                    }
                }
                if let efforts = chosenModel?.efforts, !efforts.isEmpty {
                    Section("Esforço") {
                        ForEach(efforts, id: \.self) { e in
                            Button { pendingEffort = e } label: {
                                let name = ModelPicker.effortLabel(e) ?? e
                                if e == chosenEffort { Label(name, systemImage: "checkmark") } else { Text(name) }
                            }
                        }
                    }
                }
                Section { Text("Muda a partir da próxima mensagem.") }
            }
        } label: {
            HStack(spacing: 4) {
                Text(chosenModel?.name ?? modelLabel).foregroundStyle(Theme.text)
                if chosenModel?.efforts.isEmpty == false, let e = ModelPicker.effortLabel(chosenEffort) {
                    Text(e).foregroundStyle(Theme.muted)
                }
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .font(.subheadline).lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(Theme.text.opacity(0.08), in: Capsule())
        }
        .accessibilityLabel("Modelo e esforço: \(chosenModel?.name ?? modelLabel)")
    }

    /// Prompts waiting for the agent: the PC's queue plus the ones this phone just
    /// sent while it was busy, until they show up in the conversation.
    private var queuedPrompts: [QueuedPreview] {
        let asked = Set(allItems.filter { $0.direction == "input" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
        var out = session?.queued ?? []
        for q in localQueued where !out.contains(where: { $0.id == q.id || $0.text == q.text }) { out.append(q) }
        return out.filter { !asked.contains($0.text) && !removedQueued.contains($0.id) }
    }

    @ViewBuilder private var queueTray: some View {
        if !queuedPrompts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(queuedPrompts) { q in
                    HStack(spacing: 10) {
                        Image(systemName: "clock").font(.footnote).foregroundStyle(Theme.muted)
                        Text(q.text).font(.subheadline).foregroundStyle(Theme.textSoft).lineLimit(1)
                        Spacer(minLength: 6)
                        Button("Anular") { removeQueued(q) }
                            .font(.footnote).foregroundStyle(Theme.muted)
                            .disabled(busyId != nil)
                        Button("Enviar agora") { sendNow() }
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).frame(minHeight: 30)
                            .background(Theme.elevated, in: Capsule())
                            .disabled(busyId != nil || !online)
                    }
                }
                Text("Na fila: corre quando o agente acabar o que está a fazer.").font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }

    /// Take a queued message back before it runs. The PC confirms by
    /// republishing its queue; until then the row is hidden here.
    private func removeQueued(_ q: QueuedPreview) {
        guard let client = model.client else { return }
        Task {
            busyId = "remove"
            do {
                try await client.removeQueued(sessionId: sessionId, promptId: q.id, targetDeviceId: target)
                localQueued.removeAll { $0.id == q.id }
                removedQueued.insert(q.id)
                if draft.isEmpty { draft = q.text }
                notice = "Mensagem tirada da fila. Ficou na caixa para a editares."
                Prefs.tap()
            } catch {
                actionError = "Não consegui falar com o PC. Tenta outra vez."
            }
            busyId = nil
        }
    }

    /// Stop the current turn and run the queue now.
    private func sendNow() {
        guard let client = model.client else { return }
        Task {
            busyId = "sendnow"
            do {
                try await client.sendNow(sessionId: sessionId, targetDeviceId: target)
                notice = "A parar o que estava a fazer e a correr a tua mensagem agora."
                Prefs.tap()
            } catch {
                actionError = "Não consegui falar com o PC. Tenta outra vez."
            }
            busyId = nil
        }
    }

    private var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty) && busyId == nil && model.snapshot.connected
    }

    /// "3 passos · Correu: swift test" — tap to see every step.
    @ViewBuilder private func stepsRow(_ steps: [ChatLine]) -> some View {
        let key = steps.first?.id ?? ""
        let open = expandedSteps.contains(key)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if open { expandedSteps.remove(key) } else { expandedSteps.insert(key) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(steps.count == 1 ? steps[0].text : "\(steps.count) passos · \(steps.last?.text ?? "")")
                        .font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    let diffs = steps.compactMap(\.diff)
                    if steps.count > 1, !diffs.isEmpty {
                        let added = diffs.reduce(0) { $0 + $1.added }, removed = diffs.reduce(0) { $0 + $1.removed }
                        HStack(spacing: 4) {
                            if added > 0 { Text("+\(added)").foregroundStyle(.green) }
                            if removed > 0 { Text("−\(removed)").foregroundStyle(.red) }
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            if steps.count > 1 { Text(s.text).font(.footnote).foregroundStyle(Theme.textSoft) }
                            if let diff = s.diff, !diff.lines.isEmpty {
                                DiffView(diff: diff)
                            } else if let d = s.detail, !d.isEmpty {
                                Text(d).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.muted)
                                    .lineLimit(4).textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func bubble(_ item: ChatLine) -> some View {
        let mine = item.mine
        if !mine {
            VStack(alignment: .leading, spacing: 10) {
                MarkdownText(text: item.text)
                RefCards(refs: Refs.find(item.text))
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu { copyButton(item.text) }
        } else {
        VStack(alignment: .trailing, spacing: 6) {
        if let pics = model.sentImages[sessionId + "|" + item.text], !pics.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(pics.enumerated()), id: \.offset) { _, data in
                    if let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill().frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        Text(item.text)
            .font(.body).foregroundStyle(mine ? Theme.text : Theme.textSoft)
            .textSelection(.enabled)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(mine ? Theme.amberFill : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(mine ? Theme.amberBorder : .clear, lineWidth: 1))
            .contextMenu { copyButton(item.text) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Send the draft to the PC 1.2 s after you stop typing (and "" once it is sent).
    private func shareDraftSoon(_ text: String) {
        draftTask?.cancel()
        guard text != lastSharedDraft, let client = model.client else { return }
        let id = sessionId
        draftTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            if (try? await client.saveDraft(sessionId: id, text: text)) != nil { lastSharedDraft = text }
        }
    }

    // MARK: Search in the conversation

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return visible.filter { !$0.isStep && $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.map(\.id)
    }

    private func isCurrentMatch(_ id: String) -> Bool {
        searching && !matches.isEmpty && matches[min(matchIndex, matches.count - 1)] == id
    }

    private func jump(_ step: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + step + matches.count) % matches.count
        scrollTarget = nil
        DispatchQueue.main.async { scrollTarget = matches[matchIndex] }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Procurar na conversa", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .foregroundStyle(Theme.text)
                .submitLabel(.search)
                .onSubmit { jump(1) }
                .onChange(of: query) { _, _ in
                    matchIndex = max(0, matches.count - 1)   // newest match first
                    if let last = matches.last { scrollTarget = nil; DispatchQueue.main.async { scrollTarget = last } }
                }
            Text(matches.isEmpty ? (query.count >= 2 ? "0" : "") : "\(matchIndex + 1)/\(matches.count)")
                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.muted)
            Button { jump(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(matches.isEmpty).accessibilityLabel("Resultado anterior")
            Button { jump(1) } label: { Image(systemName: "chevron.down") }
                .disabled(matches.isEmpty).accessibilityLabel("Resultado seguinte")
            Button { searching = false; query = ""; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                .accessibilityLabel("Fechar pesquisa")
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    @ViewBuilder private func copyButton(_ text: String) -> some View {
        Button { UIPasteboard.general.string = text; Prefs.tap() } label: { Label("Copiar", systemImage: "doc.on.doc") }
        ShareLink(item: text) { Label("Partilhar", systemImage: "square.and.arrow.up") }
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
            HStack(spacing: 10) {
                Button("Sempre nesta sessão") { act(p.id) { try await $0.respondToPermission(sessionId: sessionId, promptId: p.id, allow: true, scope: "session", targetDeviceId: target) } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Sempre neste projeto") { act(p.id) { try await $0.respondToPermission(sessionId: sessionId, promptId: p.id, allow: true, scope: "always", targetDeviceId: target) } }
                    .buttonStyle(SecondaryButtonStyle())
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
                Prefs.tap()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await fullLoad()
            } catch {
                actionError = "Não consegui enviar ao PC. Confirma que o PC está ligado e tenta outra vez."
            }
            busyId = nil
        }
    }

    private func send(_ text: String, source: String, images: [PromptImage] = [], now: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = model.client, !trimmed.isEmpty || !images.isEmpty else { return }
        busyId = "send"
        defer { busyId = nil }
        do {
            let wasBusy = busy
            let id = try await client.sendPrompt(sessionId: sessionId, text: trimmed, images: images, options: promptOptions, source: source, targetDeviceId: target)
            Prefs.tap()
            if !images.isEmpty {
                // Same wording the core uses when an image goes without text.
                let shown = trimmed.isEmpty ? (images.count == 1 ? "Vê a imagem em anexo." : "Vê as imagens em anexo.") : trimmed
                model.sentImages[sessionId + "|" + shown] = images.map(\.data)
            }
            if wasBusy && !now { localQueued.append(QueuedPreview(id: id, text: trimmed)) }
            if now && wasBusy { try await client.sendNow(sessionId: sessionId, targetDeviceId: target) }
            draft = ""
            if !images.isEmpty { self.images = [] }
            actionError = nil
            notice = !online ? "Resposta guardada. Corre quando o PC ligar."
                : (wasBusy && !now) ? "Na fila. Corre quando o agente acabar." : "Resposta enviada. À espera do agente…"
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
            model.cache.saveTranscript(allItems, sessionId: sessionId)
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
        model.cache.saveTranscript(allItems, sessionId: sessionId)
        if added.contains(where: { $0.direction == "output" }) { notice = nil }
        let id = sessionId
        Task { try? await model.client?.markRead(sessionId: id) }
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

/// Where the end of the conversation sits inside the visible scroll area.
private struct EndOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
