import Foundation

/// One desktop's plan usage, as published by the desktop session (HANDOFF 6a):
/// `planUsageBroadcast { deviceId, encryptedUsage, usageIv, updatedAt }`, the
/// plaintext being `{ v, desktopName, updatedAt, plans: [...] }`.
public struct PlanUsage: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var name: String
        public var percent: Double
        public var resetsAt: String?
    }
    public struct Plan: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var percent: Double
        public var windows: [Window]

        private enum CodingKeys: String, CodingKey { case id, label, percent, windows }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            label = (try? c.decode(String.self, forKey: .label)) ?? id
            percent = (try? c.decode(Double.self, forKey: .percent)) ?? 0
            windows = (try? c.decode([Window].self, forKey: .windows)) ?? []
        }
        public init(id: String, label: String, percent: Double, windows: [Window] = []) {
            self.id = id; self.label = label; self.percent = percent; self.windows = windows
        }

        /// When the busiest window resets, if the desktop said.
        public var nextReset: Date? {
            let f = ISO8601DateFormatter()
            let busiest = windows.max { $0.percent < $1.percent }
            return busiest?.resetsAt.flatMap { f.date(from: $0) }
        }
    }

    public var deviceId: String = ""
    public var desktopName: String?
    public var updatedAt: Double
    public var plans: [Plan]

    private enum CodingKeys: String, CodingKey { case desktopName, updatedAt, plans }

    public init(deviceId: String, desktopName: String?, updatedAt: Double, plans: [Plan]) {
        self.deviceId = deviceId; self.desktopName = desktopName; self.updatedAt = updatedAt; self.plans = plans
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        desktopName = try? c.decodeIfPresent(String.self, forKey: .desktopName)
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        plans = (try? c.decode([Plan].self, forKey: .plans)) ?? []
    }

    public var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }

    /// Decrypt a broadcast. Returns nil when it is not readable with this key.
    public static func decrypt(deviceId: String, encryptedUsage: String, usageIv: String, crypto: SyncCrypto) -> PlanUsage? {
        guard let json = try? crypto.decrypt(ciphertext: encryptedUsage, iv: usageIv),
              var usage = try? JSONDecoder().decode(PlanUsage.self, from: Data(json.utf8)) else { return nil }
        usage.deviceId = deviceId
        return usage
    }
}

/// Which computer should run work for a project.
public enum DesktopRouting {
    /// The online desktop that reported holding this project (by its encrypted
    /// project id), else the first online desktop, else nil.
    public static func desktop(forEncryptedProjectId encrypted: String?, devices: [DeviceInfo]) -> DeviceInfo? {
        let online = devices.filter { $0.type == "desktop" && $0.isOnline == true }
        if let encrypted, let match = online.first(where: { $0.syncedProjectIds?.contains(encrypted) == true }) {
            return match
        }
        return online.first
    }
}
