import UIKit
import UserNotifications

/// Hands the APNs token and notification taps from the app delegate to AppModel.
@MainActor
final class PushBridge {
    static let shared = PushBridge()
    private(set) var token: String?
    private(set) var failed = false
    var onToken: ((String) -> Void)?
    var onOpen: ((String) -> Void)?
    /// A tap that arrived before the UI was ready (cold launch from a notification).
    var pendingOpen: String?

    func receive(token: String) {
        self.token = token
        failed = false
        onToken?(token)
    }

    func registrationFailed() { failed = true }

    func open(_ sessionId: String) {
        if let onOpen { onOpen(sessionId) } else { pendingOpen = sessionId }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushBridge.shared.receive(token: hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushBridge.shared.registrationFailed() }
    }

    /// App open: still show the banner (the server only pushes when the phone looks away).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tap on a push or local notification: open that conversation.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["sessionId"] as? String
        if let id, !id.isEmpty { Task { @MainActor in PushBridge.shared.open(id) } }
        completionHandler()
    }
}
