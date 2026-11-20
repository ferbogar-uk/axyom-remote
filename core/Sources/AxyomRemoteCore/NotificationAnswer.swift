import Foundation

/// Answering a "waiting" notification with Permitir / Recusar, without opening
/// the app. Only a single, plain permission request can be answered this way;
/// questions, plans, commits, several requests at once or destructive commands
/// still need the app, so the person sees exactly what they approve.
public enum NotificationAnswer {
    public enum Decision: Equatable, Sendable {
        case answer(PendingPermission)
        case openApp(reason: String)
        case nothingPending
    }

    public enum Outcome: Equatable, Sendable {
        case answered(allow: Bool, what: String)
        case openApp(reason: String)
        case nothingPending
        case offline
    }

    public static func decide(_ items: [TranscriptItem], allow: Bool) -> Decision {
        let permissions = PendingPrompts.permissions(in: items)
        if !PendingPrompts.questions(in: items).isEmpty { return .openApp(reason: "O agente fez uma pergunta.") }
        if !PendingPrompts.plans(in: items).isEmpty { return .openApp(reason: "O agente quer aprovação de um plano.") }
        if !PendingPrompts.commits(in: items).isEmpty { return .openApp(reason: "O agente propõe um commit.") }
        guard let p = permissions.last else { return .nothingPending }
        if permissions.count > 1 { return .openApp(reason: "Há \(permissions.count) pedidos de permissão.") }
        // Saying no is always safe; saying yes to something destructive needs the full card.
        if allow && p.isDestructive { return .openApp(reason: "O pedido é destrutivo: confirma na app.") }
        return .answer(p)
    }

    /// Short description for the confirmation notification.
    public static func describe(_ p: PendingPermission) -> String {
        let what = !p.rawCommand.isEmpty ? p.rawCommand : (!p.patternDisplayName.isEmpty ? p.patternDisplayName : p.toolName)
        return what.count > 80 ? String(what.prefix(79)) + "…" : what
    }
}

extension RemoteClient {
    /// Connect if needed (up to `timeout`), read the session, and answer its
    /// single pending permission once.
    public func answerFromNotification(sessionId: String, allow: Bool, timeout: TimeInterval = 15) async -> NotificationAnswer.Outcome {
        let deadline = Date().addingTimeInterval(timeout)
        while !currentSnapshot().connected {
            if Date() > deadline { return .offline }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let items = try? await loadTranscript(sessionId: sessionId) else { return .offline }
        switch NotificationAnswer.decide(items, allow: allow) {
        case .nothingPending: return .nothingPending
        case .openApp(let reason): return .openApp(reason: reason)
        case .answer(let p):
            let snap = currentSnapshot()
            let session = snap.sessions.first { $0.id == sessionId }
            let target = session?.hostDeviceId
                ?? DesktopRouting.desktop(forEncryptedProjectId: session?.encryptedProjectId, devices: snap.devices)?.deviceId
            do {
                try await respondToPermission(sessionId: sessionId, promptId: p.id, allow: allow, targetDeviceId: target)
                return .answered(allow: allow, what: NotificationAnswer.describe(p))
            } catch {
                return .offline
            }
        }
    }
}
