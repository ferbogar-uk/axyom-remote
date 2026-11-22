import Foundation

/// One computer in the switch at the top of the home screen.
public struct PCChoice: Equatable, Identifiable, Sendable {
    public var id: String          // deviceId
    public var name: String
    public var online: Bool
    public var sessionCount: Int
    public var attentionCount: Int
}

/// Ricardo has AXYOM on more than one PC. The phone already sees all of them through the sync
/// index; this works out which PC each session runs on so the list can show one PC at a time.
public enum PCSwitch {
    /// The PC a session runs on: the one the index names, else the online desktop that holds its project.
    public static func host(of session: FleetSession, devices: [DeviceInfo]) -> String? {
        session.hostDeviceId ?? DesktopRouting.desktop(forEncryptedProjectId: session.encryptedProjectId, devices: devices)?.deviceId
    }

    /// A nickname set on the phone wins over the name the desktop reports; blank nicknames are ignored.
    public static func displayName(_ device: DeviceInfo, nicknames: [String: String]) -> String {
        let n = nicknames[device.deviceId]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? device.name : n
    }

    /// Desktops only, online first, then by name. Counts ignore archived sessions.
    public static func choices(devices: [DeviceInfo], sessions: [FleetSession], nicknames: [String: String] = [:]) -> [PCChoice] {
        let live = sessions.filter { !$0.isArchived }
        return devices.filter { $0.type == "desktop" }
            .map { d in
                let mine = live.filter { host(of: $0, devices: devices) == d.deviceId }
                return PCChoice(id: d.deviceId, name: displayName(d, nicknames: nicknames), online: d.isOnline == true,
                                sessionCount: mine.count, attentionCount: mine.filter(\.hasPendingPrompt).count)
            }
            .sorted { ($0.online ? 0 : 1, $0.name.lowercased()) < ($1.online ? 0 : 1, $1.name.lowercased()) }
    }

    /// Only this PC's sessions (nil = all). An unknown PC id shows everything, so a PC that
    /// disappeared never leaves the list empty.
    public static func filter(_ sessions: [FleetSession], device: String?, devices: [DeviceInfo]) -> [FleetSession] {
        guard let device, devices.contains(where: { $0.deviceId == device && $0.type == "desktop" }) else { return sessions }
        return sessions.filter { host(of: $0, devices: devices) == device }
    }
}
