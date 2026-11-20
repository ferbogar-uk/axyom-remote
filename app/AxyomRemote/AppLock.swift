import SwiftUI
import LocalAuthentication

/// Face ID (or the iPhone passcode) when the app opens or comes back after
/// more than a minute away. Settings > "Pedir Face ID ao abrir" turns it off.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var locked: Bool
    private var leftAt: Date?
    private var asking = false

    init() { locked = Prefs.faceID && !DemoData.isOn }

    func wentToBackground() { leftAt = Date() }

    func cameBack() {
        guard Prefs.faceID, !DemoData.isOn else { locked = false; return }
        if let leftAt, Date().timeIntervalSince(leftAt) > 60 { locked = true }
        if locked { unlock() }
    }

    func unlock() {
        guard locked, !asking else { return }
        let context = LAContext()
        var error: NSError?
        // Device owner = Face ID with the passcode as fallback, so it never locks him out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { locked = false; return }
        asking = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Desbloquear o AXYOM") { ok, _ in
            Task { @MainActor in
                self.asking = false
                if ok { self.locked = false; self.leftAt = nil }
            }
        }
    }
}

struct LockScreen: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        ZStack {
            BrandBackdrop()
            VStack(spacing: 18) {
                BrandMark(symbol: 56)
                Button { lock.unlock() } label: {
                    Label("Desbloquear", systemImage: "faceid")
                        .font(.headline).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 24).frame(minHeight: 48)
                        .background(Theme.accent, in: Capsule())
                }
            }
        }
    }
}
