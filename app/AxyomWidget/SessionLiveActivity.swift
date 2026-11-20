import ActivityKit
import WidgetKit
import SwiftUI
import AxyomRemoteCore

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionActivityLockView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(WidgetPalette.dyn(0xFFFFFF, 0x111A26))
                .activitySystemActionForegroundColor(WidgetPalette.text)
                .widgetURL(DeepLink.session(context.attributes.sessionId).url)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("AxyomSymbol").resizable().scaledToFit().frame(width: 30, height: 30).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(SessionActivityLook.label(s), systemImage: SessionActivityLook.icon(s))
                        .font(.caption.weight(.semibold)).foregroundStyle(SessionActivityLook.color(s)).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        if !s.isDone { Text(s.sinceDate, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image("AxyomSymbol").resizable().scaledToFit().frame(width: 20, height: 20)
            } compactTrailing: {
                Image(systemName: SessionActivityLook.icon(s)).foregroundStyle(SessionActivityLook.color(s))
            } minimal: {
                Image(systemName: SessionActivityLook.icon(s)).foregroundStyle(SessionActivityLook.color(s))
            }
            .widgetURL(DeepLink.session(context.attributes.sessionId).url)
            .keylineTint(SessionActivityLook.color(s))
        }
    }
}
