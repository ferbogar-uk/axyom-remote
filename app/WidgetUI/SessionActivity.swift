import ActivityKit
import SwiftUI
import AxyomRemoteCore

/// Live Activity for one session (Dynamic Island + lock screen). The title is set on the
/// phone when it starts; the server's pushes (request #14) carry only the state.
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "working", "waiting" or "done" (same words the server pushes).
        var phase: String
        /// Unix seconds when this phase started (the server sends seconds).
        var since: Double
        var waitingCount: Int

        var sinceDate: Date { Date(timeIntervalSince1970: since) }
        var isWaiting: Bool { phase == "waiting" }
        var isDone: Bool { phase == "done" }
    }

    var sessionId: String
    var title: String
    var provider: String
}

/// Shared drawing for the island and the lock screen.
enum SessionActivityLook {
    static func color(_ s: SessionActivityAttributes.ContentState) -> Color {
        s.isWaiting ? WidgetPalette.yellow : s.isDone ? WidgetPalette.blue : WidgetPalette.green
    }
    static func label(_ s: SessionActivityAttributes.ContentState) -> String {
        s.isWaiting ? "À tua espera" : s.isDone ? "Terminou" : "A trabalhar"
    }
    static func icon(_ s: SessionActivityAttributes.ContentState) -> String {
        s.isWaiting ? "hand.raised.fill" : s.isDone ? "checkmark" : "bolt.fill"
    }
}

struct SessionActivityLockView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image("AxyomSymbolSmall").resizable().scaledToFit().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.title).font(.subheadline.weight(.semibold)).foregroundStyle(WidgetPalette.text).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(SessionActivityLook.color(state)).frame(width: 8, height: 8)
                    Text(SessionActivityLook.label(state)).font(.caption).foregroundStyle(WidgetPalette.muted)
                    if !state.isDone {
                        Text(state.sinceDate, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(WidgetPalette.muted)
                    }
                }
            }
            Spacer(minLength: 6)
            if state.isWaiting {
                Text("Abrir").font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.06, green: 0.08, blue: 0.11))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(WidgetPalette.accent, in: Capsule())
            }
        }
        .padding(14)
    }
}
