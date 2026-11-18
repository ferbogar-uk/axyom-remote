import SwiftUI

@main
struct AxyomRemoteApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

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
    }
}
