import SwiftUI
import AxyomRemoteCore

/// Read-only conversation of one session. Sending a reply and approving from
/// the phone need the exact desktop payloads (HANDOFF section 8), so there is
/// deliberately no input box here yet: a box that does nothing would be a lie.
struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    let sessionId: String

    @State private var items: [TranscriptItem] = []
    @State private var loading = true
    @State private var failure: String?

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
                Text("Responder e aprovar a partir do iPhone ainda não está disponível. Faz-o no PC por agora.")
                    .font(.footnote).foregroundStyle(Theme.muted).card()
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(session?.title ?? "Sessão")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
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

    private func load() async {
        guard let client = model.client else { return }
        do {
            let all = try await client.loadTranscript(sessionId: sessionId)
            items = all.filter { !$0.hidden && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            failure = nil
        } catch {
            failure = "Não consegui ler esta sessão. Puxa para baixo para tentar outra vez."
        }
        loading = false
    }
}
