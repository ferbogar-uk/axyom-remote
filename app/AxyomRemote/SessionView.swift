import SwiftUI
import AxyomRemoteCore

/// Conversation of one session. Approve, deny and stop are real (they send the
/// PC the same control messages the desktop understands). Replying with text is
/// deliberately not here yet: a box that does nothing would be a lie.
struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    let sessionId: String

    @State private var items: [TranscriptItem] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var allItems: [TranscriptItem] = []
    @State private var busyId: String?
    @State private var actionError: String?

    private var session: FleetSession? { model.snapshot.sessions.first { $0.id == sessionId } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if loading && items.isEmpty { ProgressView().tint(Theme.amber).frame(maxWidth: .infinity).padding(.top, 40) }
                if let failure { Text(failure).font(.subheadline).foregroundStyle(Theme.danger).card() }
                ForEach(items) { item in bubble(item) }
                if !loading && items.isEmpty && failure == nil {
                    Text("Esta sessão ainda não tem mensagens legíveis.").font(.subheadline).foregroundStyle(Theme.muted)
                }
                ForEach(PendingPrompts.permissions(in: allItems)) { p in permissionCard(p) }
                if let actionError { Text(actionError).font(.subheadline).foregroundStyle(Theme.danger).card() }
                Text("Responder por texto ainda não está disponível. Aprovar, recusar e parar já funcionam.")
                    .font(.footnote).foregroundStyle(Theme.muted).card()
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(session?.title ?? "Sessão")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Parar") { Task { await stop() } }
                    .tint(Theme.danger)
                    .disabled(!model.pcStatus.isOnline || busyId != nil)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func bubble(_ item: TranscriptItem) -> some View {
        let mine = item.direction == "input"
        Text(item.text)
            .font(.body).foregroundStyle(mine ? Theme.text : Theme.textSoft)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(mine ? Theme.amberFill : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(mine ? Theme.amberBorder : .clear, lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

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
                Button("Recusar") { Task { await answer(p, allow: false) } }.buttonStyle(SecondaryButtonStyle())
                Button("Aprovar uma vez") { Task { await answer(p, allow: true) } }.buttonStyle(PrimaryButtonStyle())
            }
            .disabled(busyId != nil || !model.pcStatus.isOnline)
        }
        .card(fill: Theme.amberSurface, stroke: Theme.amberBorder)
    }

    private func answer(_ p: PendingPermission, allow: Bool) async {
        guard let client = model.client else { return }
        busyId = p.id
        do {
            try await client.respondToPermission(sessionId: sessionId, promptId: p.id, allow: allow, targetDeviceId: model.desktopDeviceId)
            actionError = nil
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await load()
        } catch {
            actionError = "Não consegui enviar a resposta ao PC. Confirma que o PC está ligado e tenta outra vez."
        }
        busyId = nil
    }

    private func stop() async {
        guard let client = model.client else { return }
        busyId = "stop"
        do {
            try await client.cancel(sessionId: sessionId, targetDeviceId: model.desktopDeviceId)
            actionError = nil
        } catch {
            actionError = "Não consegui enviar o pedido de paragem ao PC. Confirma que o PC está ligado."
        }
        busyId = nil
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            let all = try await client.loadTranscript(sessionId: sessionId)
            allItems = all
            items = all.filter { !$0.hidden && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            failure = nil
        } catch {
            failure = "Não consegui ler esta sessão. Puxa para baixo para tentar outra vez."
        }
        loading = false
    }
}
