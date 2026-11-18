import SwiftUI
import AxyomRemoteCore

/// Small round badge that tells the agents apart at a glance (Claude, Codex,
/// Gemini, Grok, Cursor, OpenCode). Original monograms in AXYOM's own palette:
/// the companies' logos are their trademarks and are not copied into the app.
struct AgentBadge: View {
    let provider: String
    var size: CGFloat = 28

    private var style: (letters: String, fill: Color, ink: Color) {
        let p = provider.lowercased()
        if p.hasPrefix("claude") { return ("Cl", Color(hex: 0xD9895B), Color(hex: 0x1A1210)) }
        if p.contains("codex") || p.hasPrefix("openai") { return ("Cx", Color(hex: 0xE5E7EB), Color(hex: 0x0B0F14)) }
        if p.contains("gemini") { return ("Ge", Color(hex: 0x6EA8FE), Color(hex: 0x0B1426)) }
        if p.hasPrefix("grok") { return ("Gk", Color(hex: 0x9AA4B2), Color(hex: 0x0B0F14)) }
        if p.hasPrefix("cursor") { return ("Cu", Color(hex: 0x68D6A2), Color(hex: 0x08140F)) }
        if p.hasPrefix("opencode") { return ("Oc", Color(hex: 0xC7A6FF), Color(hex: 0x150E24)) }
        let name = ProviderName.display(provider)
        return (String(name.prefix(2)), Theme.border, Theme.text)
    }

    var body: some View {
        let s = style
        Text(s.letters)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(s.ink)
            .frame(width: size, height: size)
            .background(s.fill, in: Circle())
            .accessibilityLabel(ProviderName.display(provider))
    }
}

/// Plan usage from the PC (Claude, Codex, ...), one compact line per plan.
struct PlanUsageStrip: View {
    let usage: [PlanUsage]

    var body: some View {
        if let latest = usage.first, !latest.plans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Uso do plano").sectionLabel()
                    Spacer()
                    Text("atualizado \(RelativeAge.portuguese(from: latest.updatedDate))").font(.caption).foregroundStyle(Theme.muted)
                }
                ForEach(latest.plans) { plan in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(plan.label).font(.subheadline).foregroundStyle(Theme.text)
                            Spacer()
                            if let reset = plan.nextReset, reset > Date() {
                                Text("renova \(Self.until(reset))").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Text("\(Int(plan.percent.rounded()))%").font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Self.tint(plan.percent))
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.border)
                                Capsule().fill(Self.tint(plan.percent))
                                    .frame(width: max(4, g.size.width * min(1, plan.percent / 100)))
                            }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
        }
    }

    static func tint(_ percent: Double) -> Color {
        percent >= 90 ? Theme.danger : percent >= 70 ? Theme.amber : Theme.green
    }

    static func until(_ date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if minutes < 60 { return "em \(minutes) min" }
        let hours = minutes / 60
        return hours < 48 ? "em \(hours) h" : "em \(hours / 24) dias"
    }
}

/// "claude-code:opus" -> "Opus", "gemini-2.5-flash" -> "Gemini 2.5 Flash".
enum ModelName {
    static func display(_ model: String?, provider: String?) -> String {
        guard var m = model, !m.isEmpty else { return provider.map { ProviderName.display($0) } ?? "Modelo" }
        if let colon = m.lastIndex(of: ":") { m = String(m[m.index(after: colon)...]) }
        let words = m.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").map { w -> String in
                let s = String(w)
                return s.first?.isNumber == true ? s : s.prefix(1).uppercased() + s.dropFirst()
            }
        return words.joined(separator: " ")
    }
}
