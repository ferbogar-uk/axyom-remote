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

/// Plan usage in one line of small rings (A).
struct UsageRings: View {
    let usage: [PlanUsage]
    var body: some View {
        if let latest = usage.first, !latest.plans.isEmpty {
            HStack(spacing: 14) {
                ForEach(latest.plans) { p in
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().stroke(Theme.border, lineWidth: 3)
                            Circle().trim(from: 0, to: min(1, p.percent / 100))
                                .stroke(p.percent >= 80 ? Theme.danger : Theme.textSoft, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.label).font(.caption2).foregroundStyle(Theme.muted)
                            Text("\(Int(p.percent.rounded()))%").font(.footnote.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.text)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Uso do plano")
        }
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
            Text(request ?? "Pede uma resposta. Abre para ver o pedido.")
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
