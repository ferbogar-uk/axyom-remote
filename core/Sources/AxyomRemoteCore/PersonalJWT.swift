import Foundation
import Crypto

/// Short-lived HS256 tokens for the owner's sync server, minted on the phone
/// from the personal key (the key itself is never sent). Same shape as
/// `axyomSyncCredentials.ts` on the desktop and `verifyJwt` on the server.
public enum PersonalJWT {
    public static let lifetime: TimeInterval = 300

    public static func mint(secret: String, sub: String, org: String, now: Date = Date(), lifetime: TimeInterval = lifetime) -> String {
        let iat = Int(now.timeIntervalSince1970)
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        // Fixed key order so the token is reproducible in tests.
        let body = #"{"sub":"\#(escape(sub))","organization_id":"\#(escape(org))","iat":\#(iat),"exp":\#(iat + Int(lifetime))}"#
        let signingInput = base64URL(Data(header.utf8)) + "." + base64URL(Data(body.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return signingInput + "." + base64URL(Data(mac))
    }

    /// Seconds left before `exp`, or nil when the token cannot be read.
    public static func secondsLeft(_ jwt: String, now: Date = Date()) -> TimeInterval? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3, let data = fromBase64URL(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return exp - now.timeIntervalSince1970
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func fromBase64URL(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = b.count % 4
        if pad > 0 { b += String(repeating: "=", count: 4 - pad) }
        return Data(base64Encoded: b)
    }
}
