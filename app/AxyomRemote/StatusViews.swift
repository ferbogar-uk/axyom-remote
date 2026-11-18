import SwiftUI

/// One short red line when the phone cannot reach the server, like Claude's
/// "You're offline" notice. Never shows raw errors (they can carry the token).
struct OfflineBanner: View {
    let message: String?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message == nil ? "arrow.triangle.2.circlepath" : "wifi.slash")
                .font(.footnote.weight(.semibold))
            Text(message.map { "\($0). Volto a ligar sozinho." } ?? "A ligar ao servidor…")
                .font(.footnote.weight(.medium))
                .lineLimit(2)
        }
        .foregroundStyle(message == nil ? Theme.muted : Theme.danger)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((message == nil ? Theme.elevated : Theme.danger.opacity(0.12)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Three dots that pulse in turn, beside what the agent is doing
/// ("A correr um comando…"), like the Claude app's running indicator.
struct WorkingLine: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 0.12, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        let phase = (sin(t * 4 - Double(i) * 0.9) + 1) / 2
                        Circle().fill(Theme.accent)
                            .frame(width: 7, height: 7)
                            .opacity(reduceMotion ? 0.8 : 0.35 + 0.65 * phase)
                            .offset(y: reduceMotion ? 0 : -2 * phase)
                    }
                }
            }
            .frame(width: 30, height: 12)
            Text(label + "…").font(.subheadline).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
