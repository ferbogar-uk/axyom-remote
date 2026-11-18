import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Azure neural voice through the owner's sync server (`/voice/status`,
/// `/voice/tts`, see axyom-backend sync/PROTOCOL.md). The Azure key never
/// reaches the phone: requests carry the same short personal JWT as the socket.
public enum NeuralVoice {
    public struct Option: Decodable, Equatable, Sendable {
        public let id: String
        public let lang: String
        public let label: String
        public init(id: String, lang: String, label: String) { self.id = id; self.lang = lang; self.label = label }
    }

    public struct Status: Decodable, Equatable, Sendable {
        public let configured: Bool
        public let defaultVoice: String?
        public let voices: [Option]
        public let maxChars: Int
        public let usedChars: Int
        public let monthlyCharCap: Int

        enum CodingKeys: String, CodingKey { case configured, defaultVoice, voices, maxChars, usedChars, monthlyCharCap }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            configured = try c.decodeIfPresent(Bool.self, forKey: .configured) ?? false
            defaultVoice = try c.decodeIfPresent(String.self, forKey: .defaultVoice)
            voices = (try? c.decodeIfPresent([Option].self, forKey: .voices)) ?? []
            maxChars = try c.decodeIfPresent(Int.self, forKey: .maxChars) ?? 3000
            usedChars = try c.decodeIfPresent(Int.self, forKey: .usedChars) ?? 0
            monthlyCharCap = try c.decodeIfPresent(Int.self, forKey: .monthlyCharCap) ?? 0
        }
        public init(configured: Bool, defaultVoice: String?, voices: [Option], maxChars: Int, usedChars: Int, monthlyCharCap: Int) {
            self.configured = configured; self.defaultVoice = defaultVoice; self.voices = voices
            self.maxChars = maxChars; self.usedChars = usedChars; self.monthlyCharCap = monthlyCharCap
        }
        /// Out of this month's characters: speak with the iPhone voice instead.
        public var exhausted: Bool { monthlyCharCap > 0 && usedChars >= monthlyCharCap }
    }

    static func base(_ pairing: PairingPayload) -> String {
        var b = pairing.server
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    static func token(_ pairing: PairingPayload, now: Date) -> String {
        PersonalJWT.mint(secret: pairing.key, sub: pairing.member, org: pairing.org, now: now)
    }

    public static func statusRequest(pairing: PairingPayload, now: Date = Date()) -> URLRequest? {
        guard let url = URL(string: base(pairing) + "/voice/status") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.setValue("Bearer " + token(pairing, now: now), forHTTPHeaderField: "Authorization")
        return r
    }

    /// `voice` nil = the server's default (the voice picked on the desktop).
    /// `rateMultiplier` is the app's reading speed (1.0 = normal).
    public static func ttsRequest(pairing: PairingPayload, text: String, voice: String?, rateMultiplier: Double = 1, now: Date = Date()) -> URLRequest? {
        guard let url = URL(string: base(pairing) + "/voice/tts") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("Bearer " + token(pairing, now: now), forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": text]
        if let voice, !voice.isEmpty { body["voice"] = voice }
        let pct = ratePercent(rateMultiplier)
        if pct != 0 { body["rate"] = pct }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return r
    }

    /// 1.25 → 25, 0.92 → -8; kept inside the server's -50…100.
    public static func ratePercent(_ multiplier: Double) -> Int {
        Int(((multiplier - 1) * 100).rounded()).clamped(-50, 100)
    }

    /// Split a reply into pieces that each fit one request, at sentence ends
    /// when possible. Small pieces start playing sooner; the first one is the
    /// shortest so the voice starts quickly.
    public static func chunks(_ text: String, first: Int = 220, rest: Int = 900, max: Int = 3000) -> [String] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var sentences: [String] = []
        var current = ""
        for ch in clean {
            current.append(ch)
            if ".!?\n".contains(ch) {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        var out: [String] = []
        var piece = ""
        func limit() -> Int { Swift.min(out.isEmpty ? first : rest, max) }
        func flush() { if !piece.isEmpty { out.append(piece); piece = "" } }
        for s in sentences {
            var s = s
            // A single sentence longer than the hard limit is cut at spaces.
            while s.count > max {
                flush()
                let cut = s.prefix(max)
                let at = cut.lastIndex(of: " ") ?? cut.endIndex
                out.append(String(s[..<at]).trimmingCharacters(in: .whitespaces))
                s = String(s[at...]).trimmingCharacters(in: .whitespaces)
            }
            if piece.isEmpty { piece = s }
            else if piece.count + 1 + s.count <= limit() { piece += " " + s }
            else { flush(); piece = s }
        }
        flush()
        return out
    }
}

private extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.max(lo, Swift.min(hi, self)) }
}
