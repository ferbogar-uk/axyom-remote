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

    private static var base: [String: Any]? { item(account) }

    private static func item(_ account: String) -> [String: Any]? {
        guard let group else { return nil }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecAttrAccessGroup as String: group]
    }

    static func save(_ context: PushContent.Context) { write(context, to: base) }

    /// What the home-screen widget shows (same shared group, its own item).
    static func saveWidget(_ snap: WidgetSnapshot) { write(snap, to: item("widget"), unixDates: true) }

    static func loadWidget() -> WidgetSnapshot? {
        guard var query = item("widget") else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to base: [String: Any]?, unixDates: Bool = false) {
        let e = JSONEncoder()
        if unixDates { e.dateEncodingStrategy = .secondsSince1970 }
        guard let base, let data = try? e.encode(value) else { return }
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
        for b in [base, item("widget")].compactMap({ $0 }) { SecItemDelete(b as CFDictionary) }
    }
}
