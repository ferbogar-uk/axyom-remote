import Foundation

/// Usage colour like Ricardo asked (20 Nov 2026): compare what was used with
/// how much of the window has passed. The mark sits at the end of the current
/// step (hour for the 5-hour window, day for the weekly one): first hour → 20 %,
/// second hour → 40 %… Green while under the mark, amber once past it, red
/// from 80 % of the whole window.
public enum UsagePace {
    public enum Status: Int, Comparable, Sendable {
        case ok = 0, ahead = 1, critical = 2
        public static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Reading: Equatable, Sendable {
        public let percent: Double
        /// Where usage should be by the end of the current step, 0…1 (nil = unknown window length).
        public let mark: Double?
        public let status: Status
        /// "5 horas", "7 dias"…
        public let windowLabel: String?
        public let resetsAt: Date?
    }

    public static let criticalPercent = 80.0

    /// Window length from its name ("Session", "5-hour", "Weekly", "7-day", "Fable (Weekly)").
    public static func duration(of name: String) -> (total: TimeInterval, step: TimeInterval, label: String)? {
        let n = name.lowercased()
        if n.contains("week") || n.contains("7-day") || n.contains("7 day") || n.contains("seman") {
            return (7 * 86_400, 86_400, "7 dias")
        }
        if n.contains("session") || n.contains("5-hour") || n.contains("5 hour") || n.contains("5h") || n.contains("sess") {
            return (5 * 3_600, 3_600, "5 horas")
        }
        if n.contains("day") || n.contains("dia") { return (86_400, 3_600 * 4, "1 dia") }
        if n.contains("month") || n.contains("mês") || n.contains("mes") { return (30 * 86_400, 7 * 86_400, "30 dias") }
        return nil
    }

    public static func read(name: String, percent: Double, resetsAt: Date?, now: Date = Date()) -> Reading {
        var mark: Double?
        let window = duration(of: name)
        if let window, let resetsAt {
            let left = max(0, resetsAt.timeIntervalSince(now))
            let elapsed = min(window.total, max(0, window.total - left))
            let stepEnd = min(window.total, (floor(elapsed / window.step) + 1) * window.step)
            mark = stepEnd / window.total
        }
        let status: Status
        if percent >= criticalPercent { status = .critical }
        else if let mark, percent > mark * 100 + 0.5 { status = .ahead }
        else { status = .ok }
        return Reading(percent: percent, mark: mark, status: status, windowLabel: window?.label, resetsAt: resetsAt)
    }

    /// The reading a plan's ring shows: the shortest window's number and mark
    /// (like the desktop's sidebar: Claude 49 % = the 5-hour session), coloured by
    /// the worst of all its windows.
    public static func ring(_ plan: PlanUsage.Plan, now: Date = Date()) -> Reading {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let readings = plan.windows.map { w in
            read(name: w.name, percent: w.percent, resetsAt: w.resetsAt.flatMap { f.date(from: $0) ?? plain.date(from: $0) }, now: now)
        }
        func pressure(_ r: Reading) -> Double { r.percent / 100 - (r.mark ?? 1) }
        guard let worst = readings.max(by: { a, b in
            a.status != b.status ? a.status < b.status : pressure(a) < pressure(b)
        }) else {
            return read(name: plan.label, percent: plan.percent, resetsAt: plan.nextReset, now: now)
        }
        let shortest = zip(plan.windows, readings).min { (duration(of: $0.0.name)?.total ?? .infinity) < (duration(of: $1.0.name)?.total ?? .infinity) }?.1 ?? worst
        return Reading(percent: shortest.percent, mark: shortest.mark, status: worst.status,
                       windowLabel: shortest.windowLabel, resetsAt: shortest.resetsAt)
    }
}
