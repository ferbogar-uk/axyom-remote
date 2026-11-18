import Foundation
import Crypto
import _CryptoExtras

/// End-to-end encryption shared with the AXYOM desktop.
///
/// Must stay bit-identical to `packages/runtime/src/sync/encryptionKey.ts` and
/// `collabV3Crypto.ts` in the app repo: PBKDF2-SHA256, 100 000 rounds, salt
/// `nimbalyst:<memberId>`, AES-256-GCM with a 12-byte IV, ciphertext+tag and
/// IV as standard base64. Changing any of it makes every synced row unreadable.
public struct SyncCrypto: Sendable {
    public static let pbkdf2Rounds = 100_000

    public let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    /// Derive the session key from the pairing seed (never leaves the devices).
    public init(seed: String, memberId: String) throws {
        self.key = try SyncCrypto.deriveKey(seed: seed, memberId: memberId)
    }

    public static func salt(memberId: String) -> String {
        "nimbalyst:\(memberId)"
    }

    public static func deriveKey(seed: String, memberId: String) throws -> SymmetricKey {
        try KDF.Insecure.PBKDF2.deriveKey(
            from: Data(seed.utf8),
            salt: Data(salt(memberId: memberId).utf8),
            using: .sha256,
            outputByteCount: 32,
            unsafeUncheckedRounds: pbkdf2Rounds
        )
    }

    public struct Sealed: Equatable, Sendable {
        public let ciphertext: String
        public let iv: String
    }

    public enum CryptoError: Error, Equatable {
        case badBase64
        case badUTF8
    }

    public func encrypt(_ plaintext: String, iv fixedIV: Data? = nil) throws -> Sealed {
        let nonce = try fixedIV.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: nonce)
        // WebCrypto's AES-GCM output is ciphertext || 16-byte tag.
        let joined = box.ciphertext + box.tag
        return Sealed(ciphertext: joined.base64EncodedString(), iv: Data(nonce).base64EncodedString())
    }

    /// Seal raw bytes (images). Same wire format as text.
    public func encryptData(_ data: Data) throws -> Sealed {
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(data, using: key, nonce: nonce)
        return Sealed(ciphertext: (box.ciphertext + box.tag).base64EncodedString(), iv: Data(nonce).base64EncodedString())
    }

    public func decryptData(ciphertext: String, iv: String) throws -> Data {
        guard let joined = Data(base64Encoded: ciphertext),
              let ivData = Data(base64Encoded: iv),
              joined.count >= 16 else { throw CryptoError.badBase64 }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: ivData),
                                        ciphertext: joined.prefix(joined.count - 16), tag: joined.suffix(16))
        return try AES.GCM.open(box, using: key)
    }

    public func decrypt(ciphertext: String, iv: String) throws -> String {
        guard let joined = Data(base64Encoded: ciphertext),
              let ivData = Data(base64Encoded: iv),
              joined.count >= 16 else { throw CryptoError.badBase64 }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: ivData),
            ciphertext: joined.prefix(joined.count - 16),
            tag: joined.suffix(16)
        )
        let plain = try AES.GCM.open(box, using: key)
        guard let text = String(data: plain, encoding: .utf8) else { throw CryptoError.badUTF8 }
        return text
    }
}
