import SwiftUI
import AxyomRemoteCore

/// Home screen "Comando" (option A, approved 2026-11-18).
/// Shows only what the sync index really carries: who is waiting for you,
/// who is working, what happened last, and the plan usage the PC publishes.
/// Approving and replying happen inside each session.
struct ComandoView: View {
    @EnvironmentObject private var model: AppModel
    @State private var project: String?
    @State private var showNew = false
    @State private var showVoice = false
    @State private var path: [String] = []
    @State private var showSettings = false
    @State private var search = ""
    /// Parents whose sub-agents are folded (like the chevrons on the PC).
    @State private var collapsed: Set<String> = []

    /// What the new-session sheet starts with (long-press menu fills it).
    @State private var newPreset: (project: String?, parent: FleetSession?, manager: Bool) = (nil, nil, false)
    @State private var usagePlan: PlanUsage.Plan?

    var body: some View {
        NavigationStack(path: $path) {
            let board = filtered(model.board(project: project))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statusBanner
                    UsageRings(usage: model.snapshot.planUsage) { plan in usagePlan = plan }
                    if board.projects.count > 1 { projectChips(board) }
                    searchField
                    waitingCards(board.waiting)
                    let sections = treeSections
                    ForEach(sections) { treeSection($0) }
                    if board.waiting.isEmpty && sections.isEmpty { emptyState }
                    archivedLink
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { try? await model.client?.refreshIndex() }
            .navigationDestination(for: String.self) { id in
                switch id {
                case "screen:usage": PlanUsageDetailView()
                case "screen:archived": ArchivedView()
                default: SessionView(sessionId: id.hasPrefix("talk:") ? String(id.dropFirst(5)) : id, startTalking: id.hasPrefix("talk:"))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Theme.background)
        }
        .onChange(of: model.openRequest) { _, id in
            guard let id else { return }
            path = [id]
            model.openRequest = nil
        }
        .onAppear {
            if let id = model.openRequest { path = [id]; model.openRequest = nil }
        }
        .sheet(isPresented: $showNew) {
            NewSessionSheet(board: model.board(), presetProject: newPreset.project, parent: newPreset.parent, manager: newPreset.manager)
                .environmentObject(model)
        }
        .sheet(item: $usagePlan) { PlanUsageSheet(plan: $0) }
        .sheet(isPresented: $showVoice) { VoiceView().environmentObject(model) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
        .onAppear {
            if model.isDemo && DemoData.screen == "settings" { showSettings = true }
            if model.isDemo && DemoData.screen == "usage" { usagePlan = model.snapshot.planUsage.first?.plans.first }
            if model.isDemo && DemoData.screen == "menu" { openNew(parent: model.snapshot.sessions.first { $0.id == DemoData.mainSession }) }
        }
    }

    private var pcOnline: Bool { model.pcStatus.isOnline }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image("AxyomSymbol").resizable().scaledToFit().frame(height: 34).accessibilityHidden(true)
                    Text("AXYOM").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
                }
                HStack(spacing: 6) {
                    Circle().fill(pcOnline ? Theme.green : Theme.muted).frame(width: 8, height: 8)
                    Text(pcLine).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Button { openNew() } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(pcOnline ? Theme.text : Theme.muted)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .disabled(!pcOnline)
            .accessibilityLabel("Nova sessão")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("Definições")
        }
        .padding(.top, 8)
    }

    private var pcLine: String {
        switch model.pcStatus {
        case .online(let name): return "\(name) · online"
        case .offline(let name, _): return "\(name) · offline"
        case .unknown: return model.snapshot.connected ? "Sem PC ligado" : "A ligar…"
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if !model.snapshot.connected {
            OfflineBanner(message: model.snapshot.lastError)
        } else if case .offline(_, let lastSeen) = model.pcStatus {
            VStack(alignment: .leading, spacing: 4) {
                Text("O PC não está ligado").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(lastSeen.map { "Visto \(RelativeAge.portuguese(from: $0)). " } ?? "")Podes ler as sessões. Começar sessões só funciona com o PC ligado.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .card(stroke: Theme.borderStrong)
        }
    }

    private func projectChips(_ board: FleetBoard) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Todos · \(board.projects.reduce(0) { $0 + $1.sessionCount })", on: project == nil) { project = nil }
                ForEach(board.projects) { p in
                    chip("\(p.name) · \(p.sessionCount)", on: project == p.id) { project = p.id }
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.background : Theme.text)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(on ? Theme.text : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : Theme.borderStrong, lineWidth: 1))
        }
    }

    private func waitingSection(_ sessions: [FleetSession]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("À espera de ti · \(sessions.count)").sectionLabel(Theme.text)
            ForEach(sessions) { s in
                NavigationLink(value: s.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            AgentBadge(provider: s.provider)
                            Text(s.title).font(.headline).foregroundStyle(Theme.text).lineLimit(2)
                            Spacer(minLength: 8)
                            Text("\(s.projectName) · \(ProviderName.display(s.provider))").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Text("Pede uma resposta ou aprovação. Abre para ler o pedido.").font(.subheadline).foregroundStyle(Theme.textSoft)
                    }
                    .card(fill: Theme.amberSurface, stroke: Theme.amberBorder)
                }
                .buttonStyle(.plain)
                .contextMenu { sessionMenu(s) }
            }
        }
    }

    private func workingSection(_ sessions: [FleetSession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A trabalhar · \(sessions.count)").sectionLabel()
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
                    NavigationLink(value: s.id) { row(s, trailing: "A trabalhar", tint: Theme.green) }.buttonStyle(.plain)
                        .contextMenu { sessionMenu(s) }
                    if index < sessions.count - 1 { Divider().overlay(Theme.border) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func recentSection(_ sessions: [FleetSession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recentes").sectionLabel()
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
                    NavigationLink(value: s.id) {
                        row(s, trailing: RelativeAge.portuguese(from: s.lastActivity), tint: Theme.muted)
                    }.buttonStyle(.plain)
                    .contextMenu { sessionMenu(s) }
                    if index < sessions.count - 1 { Divider().overlay(Theme.border) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func row(_ s: FleetSession, trailing: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AgentBadge(provider: s.provider)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.body).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(s.projectName) · \(ProviderName.display(s.provider))").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if s.isUnread { Circle().fill(Theme.text).frame(width: 8, height: 8).accessibilityLabel("Não lida") }
            Text(trailing).font(.footnote).foregroundStyle(tint)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ainda sem sessões").font(.headline).foregroundStyle(Theme.text)
            Text(pcOnline ? "Começa uma no PC com \"Nova sessão\"." : "Quando o PC ligar, as sessões aparecem aqui.")
                .font(.subheadline).foregroundStyle(Theme.muted)
        }
        .card()
    }

    @ViewBuilder private var archivedLink: some View {
        let count = model.snapshot.sessions.filter(\.isArchived).count
        if count > 0 {
            NavigationLink(value: "screen:archived") {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox").foregroundStyle(Theme.muted)
                    Text("Arquivadas · \(count)").font(.subheadline).foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Voice button: open the session that is waiting for you (else the latest)
    /// straight into the hands-free conversation; with no session, voice commands.
    private func talk() {
        let board = model.board()
        if let s = board.waiting.first ?? board.working.first ?? board.recent.first {
            path.append("talk:" + s.id)
        } else {
            showVoice = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Procurar sessões", text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .foregroundStyle(Theme.text)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .accessibilityLabel("Limpar pesquisa")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(Theme.elevated, in: Capsule())
    }

    /// All sessions of the chosen project, nested and grouped by day like the PC.
    private var treeSections: [SessionTree.Section] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = model.snapshot.sessions.filter { project == nil || $0.projectId == project }
        let match: (FleetSession) -> Bool = {
            q.isEmpty || $0.title.lowercased().contains(q) || $0.projectName.lowercased().contains(q)
                || ProviderName.display($0.provider).lowercased().contains(q)
        }
        // Searching shows matches flat; otherwise the PC's hierarchy.
        if !q.isEmpty {
            return SessionTree.build(all.filter(match).map { var s = $0; s.parentId = nil; return s })
        }
        return SessionTree.build(all, collapsed: collapsed)
    }

    private func treeSection(_ section: SessionTree.Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title).sectionLabel()
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, r in
                    treeRow(r)
                    if index < section.rows.count - 1 { Divider().overlay(Theme.border).padding(.leading, 14 + CGFloat(r.depth) * 22) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func treeRow(_ r: SessionTree.Row) -> some View {
        let s = r.session
        return HStack(spacing: 6) {
            if r.childCount > 0 {
                Button {
                    if collapsed.contains(s.id) { collapsed.remove(s.id) } else { collapsed.insert(s.id) }
                } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(collapsed.contains(s.id) ? 0 : 90))
                        .frame(width: 22, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed.contains(s.id) ? "Mostrar \(r.childCount) sub-agentes" : "Esconder sub-agentes")
            } else {
                Color.clear.frame(width: 22)
            }
            NavigationLink(value: s.id) {
                HStack(spacing: 10) {
                    AgentBadge(provider: s.provider)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(r.depth == 0 ? .body : .subheadline).foregroundStyle(Theme.text).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(s.isExecuting ? "A trabalhar" : RelativeAge.portuguese(from: s.lastActivity))
                                .font(.caption).foregroundStyle(s.isExecuting ? Theme.green : Theme.muted)
                            if let role = r.role { tag(role, dot: nil) }
                            if let phase = r.phase { tag(phase, dot: Theme.phaseDot(phase)) }
                        }
                    }
                    Spacer(minLength: 6)
                    if s.hasPendingPrompt { Circle().fill(Theme.phase).frame(width: 8, height: 8).accessibilityLabel("À tua espera") }
                    else if s.isUnread { Circle().fill(Theme.text).frame(width: 8, height: 8).accessibilityLabel("Não lida") }
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { sessionMenu(s) }
        }
        .padding(.leading, 6 + CGFloat(r.depth) * 22)
        .padding(.trailing, 14).padding(.vertical, 4)
    }

    /// Grey label with an optional coloured dot (phase colours stay readable but quiet).
    private func tag(_ text: String, dot: Color?) -> some View {
        HStack(spacing: 4) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(text).font(.caption2.weight(.medium)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    /// Keep only sessions whose title, project or agent match the search.
    private func filtered(_ board: FleetBoard) -> FleetBoard {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return board }
        let match: (FleetSession) -> Bool = {
            $0.title.lowercased().contains(q) || $0.projectName.lowercased().contains(q)
                || ProviderName.display($0.provider).lowercased().contains(q)
        }
        return FleetBoard(waiting: board.waiting.filter(match), working: board.working.filter(match),
                          recent: board.recent.filter(match), projects: board.projects)
    }

    /// Long-press on a session: archive it on the PC.
    @ViewBuilder private func sessionMenu(_ s: FleetSession) -> some View {
        if pcOnline {
            Button { openNew(project: s.projectId) } label: { Label("Nova sessão neste projeto", systemImage: "plus.bubble") }
            Button { openNew(project: s.projectId, manager: true) } label: { Label("Nova sessão gestora", systemImage: "person.3") }
            Button { openNew(parent: s) } label: { Label("Novo sub-agente desta sessão", systemImage: "arrow.turn.down.right") }
            Divider()
        }
        Button(role: .destructive) {
            guard let client = model.client else { return }
            let target = s.hostDeviceId ?? model.desktopId(forEncryptedProjectId: s.encryptedProjectId)
            Task { try? await client.archive(sessionId: s.id, targetDeviceId: target); Prefs.tap() }
        } label: {
            Label("Arquivar sessão", systemImage: "archivebox")
        }
        .disabled(!pcOnline)
    }

    private func openNew(project: String? = nil, parent: FleetSession? = nil, manager: Bool = false) {
        newPreset = (project, parent, manager)
        showNew = true
    }

    /// "À tua espera": what is asked, and Permitir when it is a single plain permission.
    @ViewBuilder private func waitingCards(_ sessions: [FleetSession]) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("À tua espera").sectionLabel(Theme.text)
                ForEach(sessions) { s in
                    let req = model.pendingRequests[s.id]
                    NavigationLink(value: s.id) {
                        WaitingCard(session: s, request: req?.text,
                                    onAllow: req?.canAllow == true ? { Task { await model.allowFromHome(s) } } : nil)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { sessionMenu(s) }
                }
            }
            .task(id: sessions.map(\.id).joined()) { await model.loadPendingRequests(sessions) }
        }
    }
}
