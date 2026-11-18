import Foundation
import Security
import AxyomRemoteCore

/// The pairing (server address, personal key, encryption seed) is a secret:
/// it lives only in the iOS Keychain, on this device, never in UserDefaults.
enum PairingKeychain {
    struct KeychainError: Error { let status: OSStatus }

    private static let service = "com.axyom.remote"
    private static let account = "pairing"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ pairing: PairingPayload) throws {
        let data = try JSONEncoder().encode(pairing)
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func load() -> PairingPayload? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PairingPayload.self, from: data)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}
