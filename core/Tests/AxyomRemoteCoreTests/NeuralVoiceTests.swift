import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AxyomRemoteCore

final class NeuralVoiceTests: XCTestCase {
    let pairing = PairingPayload(server: "https://sync.example/", key: "k", seed: "s", issuedAt: 0)

    func testStatusDecodesServerShape() throws {
        let json = #"{"configured":true,"defaultVoice":"pt-BR-MacerioMultilingualNeural","voices":[{"id":"pt-BR-FranciscaNeural","lang":"pt-BR","label":"Francisca"}],"maxChars":3000,"format":"x","month":"2026-11","usedChars":10,"monthlyCharCap":200000}"#
        let s = try JSONDecoder().decode(NeuralVoice.Status.self, from: Data(json.utf8))
        XCTAssertTrue(s.configured)
        XCTAssertEqual(s.voices.first?.id, "pt-BR-FranciscaNeural")
        XCTAssertFalse(s.exhausted)
        let off = try JSONDecoder().decode(NeuralVoice.Status.self, from: Data(#"{"configured":false}"#.utf8))
        XCTAssertFalse(off.configured)
    }

    func testRequestsCarryJWTAndBody() throws {
        let status = try XCTUnwrap(NeuralVoice.statusRequest(pairing: pairing))
        XCTAssertEqual(status.url?.absoluteString, "https://sync.example/voice/status")
        XCTAssertTrue(status.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ey") == true)

        let tts = try XCTUnwrap(NeuralVoice.ttsRequest(pairing: pairing, text: "Olá", voice: nil, rateMultiplier: 1.25))
        XCTAssertEqual(tts.httpMethod, "POST")
        XCTAssertEqual(tts.url?.path, "/voice/tts")
        let body = try XCTUnwrap(tts.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(body, #"{"rate":25,"text":"Olá"}"#)
        let picked = try XCTUnwrap(NeuralVoice.ttsRequest(pairing: pairing, text: "a", voice: "en-GB-RyanNeural", rateMultiplier: 1))
        XCTAssertTrue(String(data: picked.httpBody!, encoding: .utf8)!.contains("en-GB-RyanNeural"))
    }

    func testRatePercent() {
        XCTAssertEqual(NeuralVoice.ratePercent(0.92), -8)
        XCTAssertEqual(NeuralVoice.ratePercent(1.08), 8)
        XCTAssertEqual(NeuralVoice.ratePercent(3), 100)
    }

    func testChunksKeepSentencesAndLimits() {
        XCTAssertEqual(NeuralVoice.chunks("  "), [])
        XCTAssertEqual(NeuralVoice.chunks("Olá. Tudo bem?"), ["Olá. Tudo bem?"])
        let s = String(repeating: "Frase de teste com palavras. ", count: 80)
        let parts = NeuralVoice.chunks(s)
        XCTAssertGreaterThan(parts.count, 2)
        XCTAssertLessThanOrEqual(parts[0].count, 220)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 900 && $0.hasSuffix(".") })
        XCTAssertEqual(parts.joined(separator: " "), s.trimmingCharacters(in: .whitespaces))
        let long = String(repeating: "palavra ", count: 600)   // one 4800-char "sentence"
        XCTAssertTrue(NeuralVoice.chunks(long).allSatisfy { $0.count <= 3000 })
    }
}
