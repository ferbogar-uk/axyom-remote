import Foundation

/// Whether the desktop AXYOM is reachable, worked out from the device list the
/// index room reports. Pure logic so the "PC offline" screen is testable on Linux.
public enum PCStatus: Equatable, Sendable {
    /// No desktop has ever announced itself to this account.
    case unknown
    case online(name: String)
    /// `lastSeen` is nil when the server never reported a time.
    case offline(name: String, lastSeen: Date?)

    /// Device timestamps from the sync server are milliseconds since 1970
    /// (same unit as the session index). Not yet confirmed against the live
    /// server for devices: see docs/HANDOFF.md section 8.
    public static func from(devices: [DeviceInfo]) -> PCStatus {
        let desktops = devices.filter { $0.type == "desktop" }
        if let on = desktops.first(where: { $0.isOnline == true }) {
            return .online(name: on.name)
        }
        if let last = desktops.max(by: { $0.lastActiveAt < $1.lastActiveAt }) {
            let seen: Date? = last.lastActiveAt > 0 ? Date(timeIntervalSince1970: last.lastActiveAt / 1000) : nil
            return .offline(name: last.name, lastSeen: seen)
        }
        return .unknown
    }

    public var isOnline: Bool {
        if case .online = self { return true }
        return false
    }
}

/// "há 12 min", in European Portuguese, for the offline banner and recent rows.
public enum RelativeAge {
    public static func portuguese(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "agora" }
        let minutes = seconds / 60
        if minutes < 60 { return "há \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "há \(hours) h" }
        let days = hours / 24
        return days == 1 ? "há 1 dia" : "há \(days) dias"
    }
}

/// Human names for the provider ids the desktop uses ("openai-codex" -> "Codex").
public enum ProviderName {
    public static func display(_ providerId: String) -> String {
        guard let agent = VoiceAgent.allCases.first(where: { $0.providerId == providerId }) else { return providerId }
        switch agent {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        }
    }
}
