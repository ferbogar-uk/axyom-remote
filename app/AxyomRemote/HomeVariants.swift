import SwiftUI
import AxyomRemoteCore

/// Design options for the home screen (chosen by Ricardo from simulator prints).
/// Demo only for now: `-AXYOMScreen home-a|home-b|home-c`.
enum HomeVariant: String {
    case current = "", a, b, c
    static var demo: HomeVariant {
        let s = DemoData.screen
        guard s.hasPrefix("home-") else { return .current }
        return HomeVariant(rawValue: String(s.dropFirst(5))) ?? .current
    }
}

/// Plan usage in one line of small rings (home, option A). The colour compares
/// use with time: green under the mark, amber past it, red from 80 %. The small
/// tick on each ring is the mark (end of the current hour or day). Tap a ring
/// for that plan's windows.
struct UsageRings: View {
    let usage: [PlanUsage]
    var onTap: (PlanUsage.Plan) -> Void = { _ in }

    static func color(_ s: UsagePace.Status) -> Color {
        switch s {
        case .ok: return Theme.green
        case .ahead: return Theme.phase
        case .critical: return Theme.danger
        }
    }

    var body: some View {
        if let latest = usage.first, !latest.plans.isEmpty {
            HStack(spacing: 0) {
                ForEach(latest.plans) { p in
                    let r = UsagePace.ring(p)
                    Button { onTap(p) } label: {
                        HStack(spacing: 7) {
                            UsageRing(reading: r, size: 22, line: 3)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.label).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                                Text("\(Int(r.percent.rounded()))%").font(.footnote.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.text)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.label): \(Int(r.percent.rounded())) por cento")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// One ring with its pace tick.
struct UsageRing: View {
    let reading: UsagePace.Reading
    var size: CGFloat = 22
    var line: CGFloat = 3
    var body: some View {
        ZStack {
            Circle().stroke(Theme.border, lineWidth: line)
            Circle().trim(from: 0, to: min(1, max(0.02, reading.percent / 100)))
                .stroke(UsageRings.color(reading.status), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let mark = reading.mark, mark < 1 {
                Capsule().fill(Theme.text)
                    .frame(width: 1.6, height: line + 4)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(mark * 360))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A plan's windows, like the desktop's usage panel: percentage, bar with the
/// pace mark, and when it renews.
struct PlanUsageSheet: View {
    let plan: PlanUsage.Plan
    @Environment(\.dismiss) private var dismiss

    private func resetDate(_ w: PlanUsage.Window) -> Date? {
        guard let s = w.resetsAt else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func renews(_ d: Date?) -> String {
        guard let d else { return "Renovação desconhecida" }
        let s = max(0, d.timeIntervalSinceNow)
        if s < 60 { return "Renova agora" }
        let days = Int(s / 86_400), hours = Int(s.truncatingRemainder(dividingBy: 86_400) / 3600), mins = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
        if days > 0 { return "Renova em \(days)d \(hours)h" }
        if hours > 0 { return "Renova em \(hours)h \(mins)min" }
        return "Renova em \(mins)min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AgentBadge(provider: plan.id)
                Text("Uso \(plan.label)").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Fechar")
            }
            .padding(.bottom, 8)
            let windows = plan.windows.isEmpty ? [PlanUsage.Window(name: plan.label, percent: plan.percent, resetsAt: nil)] : plan.windows
            ForEach(Array(windows.enumerated()), id: \.offset) { i, w in
                let r = UsagePace.read(name: w.name, percent: w.percent, resetsAt: resetDate(w))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.headline).foregroundStyle(Theme.text)
                            if let label = r.windowLabel { Text("Janela de \(label)").font(.caption).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Int(r.percent.rounded()))%").font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(UsageRings.color(r.status))
                            Text("usado").font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.border)
                            Capsule().fill(UsageRings.color(r.status)).frame(width: max(4, g.size.width * min(1, r.percent / 100)))
                            if let mark = r.mark, mark < 1 {
                                Rectangle().fill(Theme.text).frame(width: 2, height: 12).offset(x: g.size.width * mark - 1)
                            }
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.caption2)
                        Text(renews(r.resetsAt)).font(.caption)
                        Spacer()
                        if let mark = r.mark {
                            Text("Ritmo: até \(Int((mark * 100).rounded()))% agora").font(.caption)
                        }
                    }
                    .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 14)
                if i < windows.count - 1 { Divider().overlay(Theme.border) }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.surface)
        .presentationDetents([.medium, .large])
    }
}

/// Highest plan as a small pill for the header (B).
struct UsagePill: View {
    let usage: [PlanUsage]
    var body: some View {
        if let p = usage.first?.plans.max(by: { $0.percent < $1.percent }) {
            Text("\(p.label) \(Int(p.percent.rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.textSoft)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// "À tua espera" card that says what is asked and offers Permitir / Ver.
struct WaitingCard: View {
    let session: FleetSession
    let request: String?
    var prominent = false
    var onAllow: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentBadge(provider: session.provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    Text("\(ProviderName.display(session.provider)) · \(session.projectName)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Text(request ?? "A ler o pedido…")
                .font(.subheadline).foregroundStyle(Theme.textSoft).lineLimit(2)
            HStack(spacing: 10) {
                if let onAllow, request != nil {
                    Button(action: onAllow) {
                        Text("Permitir").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 40).background(Theme.accent, in: Capsule())
                    }
                }
                Text("Ver pedido").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 40).background(Theme.text.opacity(0.08), in: Capsule())
            }
        }
        .padding(16)
        .background(prominent ? Theme.accent.opacity(0.10) : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(prominent ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1))
    }
}

extension View {
    /// Sentence-case section title (the variants drop the spaced capitals).
    func plainSection() -> some View { font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSoft) }
}
