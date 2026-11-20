import SwiftUI
import AxyomRemoteCore

@main
struct AxyomRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared so a notification action can use it even when the app starts in the background.
    @StateObject private var model = AppModel.shared
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .overlay { if lock.locked { LockScreen(lock: lock).transition(.opacity) } }
                // Taps on the widget: axyom://session/<id> opens that conversation.
                .onOpenURL { url in
                    if case .session(let id)? = DeepLink(url) { model.openRequest = id }
                }
                .onChange(of: phase) { _, p in
                    if p == .background { lock.wentToBackground() }
                    if p == .active { lock.cameBack() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.Key.appearance) private var appearance = "system"

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.isDemo && DemoData.screen == "widget" {
                WidgetGallery(snap: WidgetSnapshot.make(sessions: model.snapshot.sessions, usage: model.snapshot.planUsage,
                                                        pc: model.pcStatus))
            } else if model.pairing == nil {
                PairingView()
            } else {
                ComandoView()
            }
        }
        .tint(Theme.amber)
        .preferredColorScheme(Prefs.colorScheme(appearance))
    }
}

/// Demo only (`-AXYOMScreen widget`): the widget's views at their real sizes, for CI screenshots.
struct WidgetGallery: View {
    let snap: WidgetSnapshot
    private func tile(_ look: WidgetLook, _ size: WidgetSize, _ w: CGFloat, _ h: CGFloat, empty: Bool = false) -> some View {
        AxyomWidgetView(snap: empty ? .empty : snap, look: look, size: size)
            .padding(16).frame(width: w, height: h)
            .background { WidgetBackdrop().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)) }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) { tile(.summary, .small, 170, 170); tile(.sessions, .small, 170, 170) }
                tile(.summary, .medium, 354, 170)
                tile(.usage, .medium, 354, 170)
                tile(.summary, .medium, 354, 170, empty: true)
                HStack(spacing: 14) {
                    AxyomWidgetView(snap: snap, look: .summary, size: .lockRect).padding(10).frame(width: 220, height: 76)
                        .background(.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                    AxyomWidgetView(snap: snap, look: .summary, size: .lockCircle).frame(width: 66, height: 66)
                }
            }
            .padding(.top, 60)
        }
    }
}
