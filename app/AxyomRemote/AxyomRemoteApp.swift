import SwiftUI

@main
struct AxyomRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared so a notification action can use it even when the app starts in the background.
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.Key.appearance) private var appearance = "system"

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.pairing == nil {
                PairingView()
            } else {
                ComandoView()
            }
        }
        .tint(Theme.amber)
        .preferredColorScheme(Prefs.colorScheme(appearance))
    }
}
