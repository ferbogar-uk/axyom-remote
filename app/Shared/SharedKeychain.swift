import Foundation
import Security
import AxyomRemoteCore

/// A Keychain item shared by the app and its notification extension (access
/// group `<team>.com.axyom.remote.shared`): session titles, agents and
/// projects, plus the pairing seed so the extension can decrypt what the
/// server passes in a push. Stays on this device, readable after first unlock.
enum SharedKeychain {
    private static let service = "com.axyom.remote.shared"
    private static let account = "push-context"

    /// "<TEAMID>.com.axyom.remote.shared", found from the group iOS gives a probe item.
    private static let group: String? = {
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: "probe",
                                    kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(probe as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = probe
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attrs = result as? [String: Any],
              let g = attrs[kSecAttrAccessGroup as String] as? String,
              let team = g.split(separator: ".").first else { return nil }
        return "\(team).com.axyom.remote.shared"
    }()

    private static var base: [String: Any]? {
        guard let group else { return nil }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecAttrAccessGroup as String: group]
    }

    static func save(_ context: PushContent.Context) {
        guard let base, let data = try? JSONEncoder().encode(context) else { return }
        let update = [kSecValueData as String: data] as CFDictionary
        if SecItemUpdate(base as CFDictionary, update) == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func load() -> PushContent.Context? {
        guard var query = base else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PushContent.Context.self, from: data)
    }

    static func clear() {
        guard let base else { return }
        SecItemDelete(base as CFDictionary)
    }
}
