import ActivityKit
import Foundation
import AxyomRemoteCore

/// Starts a Live Activity when you send something to a session from the phone, keeps it
/// in step with the session while the app is open, and hands its push token to the
/// server so it stays fresh with the app closed (request #14: state only, no text).
@MainActor
final class LiveActivities {
    static let shared = LiveActivities()
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    weak var client: RemoteClient?

    private var enabled: Bool { Prefs.liveActivity && ActivityAuthorizationInfo().areActivitiesEnabled }

    private func current(_ sessionId: String) -> Activity<SessionActivityAttributes>? {
        Activity<SessionActivityAttributes>.activities.first { $0.attributes.sessionId == sessionId }
    }

    static func state(for s: FleetSession, waitingCount: Int, since: Date = Date()) -> SessionActivityAttributes.ContentState {
        let phase = s.hasPendingPrompt ? "waiting" : s.isExecuting ? "working" : "done"
        return .init(phase: phase, since: since.timeIntervalSince1970, waitingCount: waitingCount)
    }

    /// You just sent a prompt to this session from the phone.
    func start(for s: FleetSession, waitingCount: Int) {
        guard enabled else { return }
        var st = Self.state(for: s, waitingCount: waitingCount)
        if st.isDone { st.phase = "working" }       // the prompt is on its way: it is about to work
        if let a = current(s.id) {
            Task { await a.update(ActivityContent(state: st, staleDate: nil)) }
            return
        }
        let attrs = SessionActivityAttributes(sessionId: s.id, title: s.title, provider: s.provider)
        do {
            let a = try Activity.request(attributes: attrs, content: ActivityContent(state: st, staleDate: nil), pushType: .token)
            watchToken(a)
        } catch {
            // Not allowed (Low Power, user turned it off, too many): the session still works.
        }
    }

    private func watchToken(_ a: Activity<SessionActivityAttributes>) {
        let sid = a.attributes.sessionId
        tokenTasks[sid]?.cancel()
        tokenTasks[sid] = Task { [weak self] in
            for await data in a.pushTokenUpdates {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                await self?.client?.registerActivityToken(sessionId: sid, token: hex)
            }
        }
    }

    /// Every snapshot while the app is open: follow each running activity's session.
    func follow(_ sessions: [FleetSession]) {
        let waiting = sessions.filter { $0.hasPendingPrompt && !$0.isArchived }.count
        for a in Activity<SessionActivityAttributes>.activities {
            guard let s = sessions.first(where: { $0.id == a.attributes.sessionId }) else { continue }
            let old = a.content.state
            var st = Self.state(for: s, waitingCount: waiting)
            if st.phase == old.phase { st.since = old.since }
            guard st != old else { continue }
            if st.isDone {
                end(a, final: st)
            } else {
                Task { await a.update(ActivityContent(state: st, staleDate: nil)) }
            }
        }
        // After a relaunch the token stream has to be watched again.
        for a in Activity<SessionActivityAttributes>.activities where tokenTasks[a.attributes.sessionId] == nil { watchToken(a) }
    }

    private func end(_ a: Activity<SessionActivityAttributes>, final st: SessionActivityAttributes.ContentState) {
        let sid = a.attributes.sessionId
        tokenTasks[sid]?.cancel(); tokenTasks[sid] = nil
        Task {
            await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
            await client?.endActivityToken(sessionId: sid)
        }
    }

    /// Settings switch turned off, or unpairing.
    func endAll() {
        for a in Activity<SessionActivityAttributes>.activities {
            var st = a.content.state; st.phase = "done"
            end(a, final: st)
        }
    }
}
