import Foundation

/// What the home-screen widget shows, written by the app into the shared
/// keychain item and read by the widget. Same rules as the home screen:
/// desktop dot colours and the usage-ring pace colours.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var provider: String
        public var dot: FleetSession.Dot?
    }

    public struct Ring: Codable, Equatable, Sendable {
        public var label: String
        public var percent: Int
        /// 0 ok (green), 1 ahead of pace (yellow), 2 critical (red).
        public var status: Int
        public var resetsAt: Date?
    }

    public var pcName: String?
    public var pcOnline: Bool
    public var waitingCount: Int
    public var workingCount: Int
    /// First sessions to show: the ones that need you, then working, then done and unread, then the newest.
    public var items: [Item]
    public var rings: [Ring]
    public var updatedAt: Date

    public static let empty = WidgetSnapshot(pcName: nil, pcOnline: false, waitingCount: 0, workingCount: 0, items: [], rings: [], updatedAt: .distantPast)

    public static func make(sessions: [FleetSession], usage: [PlanUsage], pc: PCStatus, now: Date = Date(), limit: Int = 6) -> WidgetSnapshot {
        let live = sessions.filter { !$0.isArchived }
        func rank(_ s: FleetSession) -> Int {
            switch s.dot {
            case .needsYou?: return 0
            case .working?: return 1
            case .done?: return 2
            case nil: return 3
            }
        }
        let ordered = live.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.lastActivity > $1.lastActivity }
        let items = ordered.prefix(limit).map { Item(id: $0.id, title: $0.title, provider: $0.provider, dot: $0.dot) }
        let rings = (usage.first?.plans ?? []).map { p -> Ring in
            let r = UsagePace.ring(p, now: now)
            return Ring(label: p.label, percent: Int(r.percent.rounded()), status: r.status.rawValue, resetsAt: r.resetsAt)
        }
        var name: String?, online = false
        switch pc {
        case .online(let n): name = n; online = true
        case .offline(let n, _): name = n
        case .unknown: break
        }
        return WidgetSnapshot(pcName: name, pcOnline: online,
                              waitingCount: live.filter { $0.dot == .needsYou }.count,
                              workingCount: live.filter { $0.dot == .working }.count,
                              items: Array(items), rings: rings, updatedAt: now)
    }

    /// Same content apart from the time it was taken (so the widget is only reloaded on a real change).
    public func sameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.updatedAt = .distantPast; b.updatedAt = .distantPast
        return a == b
    }

    /// "renova em 3h 20min" / "renova em 2d".
    public static func resetText(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let s = max(0, date.timeIntervalSince(now))
        let d = Int(s / 86_400), h = Int(s.truncatingRemainder(dividingBy: 86_400) / 3_600), m = Int(s.truncatingRemainder(dividingBy: 3_600) / 60)
        if d > 0 { return "renova em \(d)d" + (h > 0 ? " \(h)h" : "") }
        if h > 0 { return "renova em \(h)h \(m)min" }
        return "renova em \(m)min"
    }
}
