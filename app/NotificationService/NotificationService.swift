import UserNotifications
import AxyomRemoteCore

/// Rewrites the server's generic push ("Um agente terminou") into who, what
/// and where: "Claude · Análise do repositório" / "Terminou · axyom-remote".
/// Runs only when the push carries `mutable-content: 1` (request #10).
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var best: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content); return
        }
        best = content
        var payload: [String: String] = [:]
        for (k, v) in request.content.userInfo {
            if let k = k as? String, let v = v as? String { payload[k] = v }
        }
        let text = PushContent.compose(payload: payload, context: SharedKeychain.load() ?? .init())
        content.title = text.title
        content.subtitle = text.subtitle
        content.body = text.body
        if let id = payload["sessionId"], !id.isEmpty { content.threadIdentifier = id }
        // Permitir / Recusar buttons when the agent is waiting (the app checks it is a single plain permission).
        if payload["kind"] == "waiting" { content.categoryIdentifier = "AXYOM_WAITING" }
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let handler, let best { handler(best) }
    }
}
