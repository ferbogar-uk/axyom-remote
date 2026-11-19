import Foundation

/// The session list as the PC shows it: grouped by day (Hoje, Ontem, Esta
/// semana, Antes), with sub-agents and worktree sessions nested under the
/// session that started them, and the PC's role and phase tags.
public enum SessionTree {
    public struct Row: Equatable, Sendable, Identifiable {
        public let session: FleetSession
        public let depth: Int
        public let childCount: Int
        public var id: String { session.id }
        /// "Orquestrador", "Sub-agente" or nil.
        public let role: String?
        /// "Planeamento", "A implementar", … or nil.
        public let phase: String?
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let title: String
        public var rows: [Row]
        public var id: String { title }
    }

    public static func phaseLabel(_ phase: String?) -> String? {
        switch phase?.lowercased() {
        case "backlog": return "Backlog"
        case "planning": return "Planeamento"
        case "implementing": return "A implementar"
        case "validating": return "A validar"
        case "complete", "completed", "done": return "Concluído"
        default: return nil
        }
    }

    /// - Parameter collapsed: parents whose children are hidden.
    public static func build(_ sessions: [FleetSession], collapsed: Set<String> = [], now: Date = Date(),
                             calendar: Calendar = .current) -> [Section] {
        let live = sessions.filter { !$0.isArchived }
        let ids = Set(live.map(\.id))
        var children: [String: [FleetSession]] = [:]
        var roots: [FleetSession] = []
        for s in live {
            if let p = s.parentId, p != s.id, ids.contains(p) { children[p, default: []].append(s) } else { roots.append(s) }
        }
        // A family is as recent as its newest member.
        func newest(_ s: FleetSession, _ seen: Set<String> = []) -> Date {
            guard !seen.contains(s.id) else { return s.lastActivity }
            return ([s.lastActivity] + (children[s.id] ?? []).map { newest($0, seen.union([s.id])) }).max() ?? s.lastActivity
        }
        let sortedRoots = roots.sorted { ($0.isPinned ? 1 : 0, newest($0)) > ($1.isPinned ? 1 : 0, newest($1)) }

        var order: [String] = []
        var bySection: [String: [Row]] = [:]
        func add(_ s: FleetSession, depth: Int, section: String, seen: Set<String>) {
            let kids = (children[s.id] ?? []).sorted { $0.lastActivity > $1.lastActivity }
            let isLead = !kids.isEmpty && (s.agentRole == "meta-agent" || s.sessionType == "workstream" || depth == 0)
            let role: String? = depth > 0 ? (kids.isEmpty ? "Sub-agente" : nil) : (isLead ? "Orquestrador" : nil)
            bySection[section, default: []].append(Row(session: s, depth: depth, childCount: kids.count,
                                                       role: role, phase: phaseLabel(s.phase)))
            guard !collapsed.contains(s.id), depth < 3 else { return }
            for k in kids where !seen.contains(k.id) { add(k, depth: depth + 1, section: section, seen: seen.union([s.id])) }
        }
        for r in sortedRoots {
            let title = r.isPinned ? "Fixadas" : bucket(newest(r), now: now, calendar: calendar)
            if bySection[title] == nil { order.append(title) }
            add(r, depth: 0, section: title, seen: [])
        }
        let rank = ["Fixadas": 0, "Hoje": 1, "Ontem": 2, "Esta semana": 3, "Antes": 4]
        return order.sorted { (rank[$0] ?? 9) < (rank[$1] ?? 9) }.map { Section(title: $0, rows: bySection[$0] ?? []) }
    }

    static func bucket(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Hoje" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Ontem" }
        if let w = calendar.date(byAdding: .day, value: -7, to: now), date > w { return "Esta semana" }
        return "Antes"
    }
}
