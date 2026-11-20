import WidgetKit
import SwiftUI
import AppIntents
import AxyomRemoteCore

/// "Editar widget" → Vista: pick what the same widget shows.
enum WidgetView: String, AppEnum {
    case summary, sessions, usage
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Vista"
    static var caseDisplayRepresentations: [WidgetView: DisplayRepresentation] = [
        .summary: "À espera + uso",
        .sessions: "Sessões",
        .usage: "Uso dos planos",
    ]
    var look: WidgetLook { WidgetLook(rawValue: rawValue) ?? .summary }
}

struct ViewChoice: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Vista do AXYOM"
    static var description = IntentDescription("Escolhe o que o widget mostra.")
    @Parameter(title: "Vista", default: .summary) var view: WidgetView
}

struct Entry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    let look: WidgetLook
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .sample, look: .summary) }
    func snapshot(for configuration: ViewChoice, in context: Context) async -> Entry {
        // The widget gallery shows an example with real-looking content, not grey bars.
        let snap = context.isPreview ? .sample : (SharedKeychain.loadWidget() ?? .empty)
        return Entry(date: Date(), snap: snap, look: configuration.view.look)
    }
    func timeline(for configuration: ViewChoice, in context: Context) async -> Timeline<Entry> {
        // The app reloads the widget whenever its data changes; this refresh only keeps "há X min" and reset times honest.
        let e = Entry(date: Date(), snap: SharedKeychain.loadWidget() ?? .empty, look: configuration.view.look)
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
}

struct AxyomWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemLarge, .systemExtraLarge: .large
        case .accessoryRectangular: .lockRect
        case .accessoryCircular: .lockCircle
        case .accessoryInline: .lockInline
        default: .medium
        }
    }
    var body: some View {
        AxyomWidgetView(snap: entry.snap, look: entry.look, size: size, now: entry.date)
            .containerBackground(for: .widget) { WidgetBackdrop() }
            .widgetURL(entry.snap.tapURL)
    }
}

struct AxyomWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AxyomWidget", intent: ViewChoice.self, provider: Provider()) { entry in
            AxyomWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AXYOM")
        .description("Sessões à tua espera, a trabalhar e uso dos planos.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct AxyomWidgets: WidgetBundle {
    var body: some Widget {
        AxyomWidget()
        SessionLiveActivity()
    }
}
