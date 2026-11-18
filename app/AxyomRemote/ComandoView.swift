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
    @State private var showSettings = false
    @State private var search = ""

    var body: some View {
        NavigationStack {
            let board = filtered(model.board(project: project))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statusBanner
                    PlanUsageStrip(usage: model.snapshot.planUsage)
                    projectChips(board)
                    searchField
                    if !board.waiting.isEmpty { waitingSection(board.waiting) }
                    if !board.working.isEmpty { workingSection(board.working) }
                    if !board.recent.isEmpty { recentSection(board.recent) }
                    if board.waiting.isEmpty && board.working.isEmpty && board.recent.isEmpty { emptyState }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationDestination(for: String.self) { SessionView(sessionId: $0) }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar(.hidden, for: .navigationBar)
            .background(Theme.background)
        }
        .sheet(isPresented: $showNew) { NewSessionSheet(board: model.board()).environmentObject(model) }
        .sheet(isPresented: $showVoice) { VoiceView().environmentObject(model) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
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
        .padding(.horizontal, 14).frame(height: 44)
        .background(Theme.elevated, in: Capsule())
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
        Button(role: .destructive) {
            guard let client = model.client else { return }
            let target = s.hostDeviceId ?? model.desktopId(forEncryptedProjectId: s.encryptedProjectId)
            Task { try? await client.archive(sessionId: s.id, targetDeviceId: target); Prefs.tap() }
        } label: {
            Label("Arquivar sessão", systemImage: "archivebox")
        }
        .disabled(!pcOnline)
    }

    /// Floating bar like the session composer: neutral "new session", orange voice.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { showNew = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("Nova sessão em…")
                }
                .font(.headline).foregroundStyle(pcOnline ? Theme.text : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.elevated, in: Capsule())
            }
            .disabled(!pcOnline)
            Button { showVoice = true } label: {
                Image(systemName: "waveform").font(.title3.weight(.bold)).foregroundStyle(Theme.onAccent)
                    .frame(width: 48, height: 48).background(Theme.accent, in: Circle())
                    .opacity(pcOnline ? 1 : 0.45)
            }
            .disabled(!pcOnline)
            .accessibilityLabel("Falar com o AXYOM")
        }
        .padding(10)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, 12).padding(.bottom, 6)
    }
}
