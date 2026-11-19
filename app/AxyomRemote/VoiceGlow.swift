import SwiftUI

/// Glow around the composer during a voice conversation, like the Claude app:
/// blue while you talk (follows your voice), orange while the app speaks
/// (gentle pulse). Replaces the old full-screen "A ouvir…" panel.
struct VoiceGlow: View {
    let color: Color
    /// 0…1 from the microphone; nil = breathing pulse.
    let level: CGFloat?
    var cornerRadius: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let l = reduceMotion ? 0.5 : (level ?? CGFloat(0.5 + 0.5 * sin(t * 3.0)))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(0.55 + 0.4 * l), lineWidth: 1.5 + l)
                .shadow(color: color.opacity(0.35 + 0.45 * l), radius: 5 + 14 * l)
                .shadow(color: color.opacity(0.25 * l), radius: 26 * l)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Three small orange dots while the agent is thinking.
struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.7 : 0.3 + 0.7 * max(0, sin(t * 4 - Double(i) * 0.7)))
                }
            }
        }
        .accessibilityLabel("O agente está a pensar")
    }
}
