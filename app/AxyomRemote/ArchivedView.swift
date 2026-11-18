import SwiftUI
import AxyomRemoteCore

/// Sessions archived on the PC, newest first, with "Desarquivar".
struct ArchivedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var restoring: Set<String> = []

    private var archived: [FleetSession] {
        model.snapshot.sessions.filter(\.isArchived).sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        List {
            if archived.isEmpty {
                Text("Não há sessões arquivadas.").foregroundStyle(Theme.muted).listRowBackground(Theme.surface)
            }
            ForEach(archived) { s in
                HStack(spacing: 10) {
                    AgentBadge(provider: s.provider)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).foregroundStyle(Theme.text).lineLimit(1)
                        Text("\(s.projectName) · \(RelativeAge.portuguese(from: s.lastActivity))").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Button(restoring.contains(s.id) ? "A pedir…" : "Desarquivar") { restore(s) }
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(Theme.elevated, in: Capsule())
                        .buttonStyle(.plain)
                        .disabled(restoring.contains(s.id) || !model.pcStatus.isOnline)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Arquivadas")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Ask the PC to bring it back; the list updates when the PC republishes it.
    private func restore(_ s: FleetSession) {
        guard let client = model.client else { return }
        restoring.insert(s.id)
        let target = s.hostDeviceId ?? model.desktopId(forEncryptedProjectId: s.encryptedProjectId)
        Task {
            try? await client.archive(sessionId: s.id, archived: false, targetDeviceId: target)
            Prefs.tap()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            restoring.remove(s.id)
        }
    }
}

/// Every plan with its usage windows (5 hours, week…) and when each renews.
struct PlanUsageDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(model.snapshot.planUsage, id: \.deviceId) { usage in
                ForEach(usage.plans) { plan in
                    Section {
                        ForEach(Array(plan.windows.enumerated()), id: \.offset) { _, w in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(Self.windowName(w.name)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text("\(Int(w.percent.rounded()))%").font(.body.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(PlanUsageStrip.tint(w.percent))
                                }
                                ProgressView(value: min(1, max(0, w.percent / 100))).tint(PlanUsageStrip.tint(w.percent))
                                if let reset = w.resetsAt.flatMap({ ISO8601DateFormatter().date(from: $0) }) {
                                    Text(reset > Date() ? "Renova \(PlanUsageStrip.until(reset)) · \(reset.formatted(date: .abbreviated, time: .shortened))"
                                                        : "Renovou \(reset.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Theme.surface)
                        }
                        if plan.windows.isEmpty {
                            HStack {
                                Text("Uso").foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(Int(plan.percent.rounded()))%").foregroundStyle(PlanUsageStrip.tint(plan.percent))
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text(plan.label)
                    } footer: {
                        if plan.id == usage.plans.last?.id {
                            Text("\(usage.desktopName ?? "PC") · atualizado \(RelativeAge.portuguese(from: usage.updatedDate))")
                        }
                    }
                }
            }
            if model.snapshot.planUsage.isEmpty {
                Text("O PC ainda não enviou o uso dos planos.").foregroundStyle(Theme.muted).listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Uso do plano")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func windowName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "5h", "five_hour", "session": return "Últimas 5 horas"
        case "week", "weekly", "7d", "seven_day": return "Semana"
        case "month", "monthly": return "Mês"
        case "day", "daily": return "Dia"
        default: return raw
        }
    }
}
