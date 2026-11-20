import Foundation

/// One desktop's plan usage, as published by the desktop session (HANDOFF 6a):
/// `planUsageBroadcast { deviceId, encryptedUsage, usageIv, updatedAt }`, the
/// plaintext being `{ v, desktopName, updatedAt, plans: [...] }`.
public struct PlanUsage: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var name: String
        public var percent: Double
        public var resetsAt: String?
        public init(name: String, percent: Double, resetsAt: String? = nil) {
            self.name = name; self.percent = percent; self.resetsAt = resetsAt
        }
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

    /// A model the desktop's pickers offer (send `id` back as options.model).
    public struct ModelChoice: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var provider: String
        public var providerLabel: String?
        public var efforts: [String]

        private enum CodingKeys: String, CodingKey { case id, name, provider, providerLabel, efforts }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = (try? c.decode(String.self, forKey: .name)) ?? id
            provider = (try? c.decode(String.self, forKey: .provider)) ?? ""
            providerLabel = try? c.decodeIfPresent(String.self, forKey: .providerLabel)
            efforts = (try? c.decode([String].self, forKey: .efforts)) ?? []
        }
        public init(id: String, name: String, provider: String, providerLabel: String? = nil, efforts: [String] = []) {
            self.id = id; self.name = name; self.provider = provider; self.providerLabel = providerLabel; self.efforts = efforts
        }
    }

    public var deviceId: String = ""
    public var desktopName: String?
    public var updatedAt: Double
    public var plans: [Plan]
    public var models: [ModelChoice] = []
    public var defaultEffort: String?

    private enum CodingKeys: String, CodingKey { case desktopName, updatedAt, plans, models, defaultEffort }

    public init(deviceId: String, desktopName: String?, updatedAt: Double, plans: [Plan]) {
        self.deviceId = deviceId; self.desktopName = desktopName; self.updatedAt = updatedAt; self.plans = plans
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        desktopName = try? c.decodeIfPresent(String.self, forKey: .desktopName)
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        plans = (try? c.decode([Plan].self, forKey: .plans)) ?? []
        if var list = try? c.nestedUnkeyedContainer(forKey: .models) {
            var out: [ModelChoice] = []
            while !list.isAtEnd {
                if let m = try? list.decode(ModelChoice.self) { out.append(m) } else { _ = try? list.decode(JSONValue.self) }
            }
            models = out
        }
        defaultEffort = try? c.decodeIfPresent(String.self, forKey: .defaultEffort)
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

/// Model and effort choices for one session.
public enum ModelPicker {
    /// Models the session can switch to: same provider (the desktop ignores a
    /// model from another provider on a session that already has messages).
    public static func choices(for provider: String, in models: [PlanUsage.ModelChoice]) -> [PlanUsage.ModelChoice] {
        let p = provider.lowercased()
        let same = models.filter { $0.provider.lowercased() == p || $0.id.lowercased().hasPrefix(p + ":") }
        return same
    }

    /// The entry for the session's current model id, if the desktop listed it.
    public static func current(_ modelId: String?, in models: [PlanUsage.ModelChoice]) -> PlanUsage.ModelChoice? {
        guard let modelId else { return nil }
        return models.first { $0.id == modelId }
    }

    public static func effortLabel(_ key: String?) -> String? {
        guard let key else { return nil }
        return EffortLevels.all.first { $0.key == key }?.label ?? key.capitalized
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
