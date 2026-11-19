import XCTest
@testable import AxyomRemoteCore

final class LiveReplyTests: XCTestCase {
    func testSentencesAreHandedOutOnceAsTheyComplete() {
        var f = SentenceFeeder()
        XCTAssertEqual(f.feed("Olá"), [])
        XCTAssertEqual(f.feed("Olá, Ricardo. Vou"), ["Olá, Ricardo."])
        XCTAssertEqual(f.feed("Olá, Ricardo. Vou correr os testes"), [])
        XCTAssertEqual(f.feed("Olá, Ricardo. Vou correr os testes. Depois"), ["Vou correr os testes."])
        XCTAssertEqual(f.finish("Olá, Ricardo. Vou correr os testes. Depois aviso."), "Depois aviso.")
        XCTAssertNil(f.finish("Olá, Ricardo. Vou correr os testes. Depois aviso."))
    }

    func testDecimalsAndNewReplies() {
        var f = SentenceFeeder()
        XCTAssertEqual(f.feed("Custa 3.5 libras. Ok"), ["Custa 3.5 libras."])
        XCTAssertEqual(f.feed("Outra resposta. "), ["Outra resposta."])
    }

    func testStreamFramesUpdateLiveText() async throws {
        let crypto = try SyncCrypto(seed: "seed", memberId: "owner")
        let box = SocketBox()
        let pairing = PairingPayload(server: "https://sync.example", key: "k", seed: "seed", issuedAt: 0)
        let phone = DeviceInfo(deviceId: "p", name: "iPhone", type: "mobile", platform: "ios", connectedAt: 0, lastActiveAt: 0)
        let client = RemoteClient(pairing: pairing, crypto: crypto, device: phone,
                                  factory: { url in box.make(url) }, sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
        await client.start()
        await assertEventually { !box.sockets.isEmpty }
        let sealed = try crypto.encrypt("Estou a escrever")
        box.sockets[0].push(#"{"type":"sessionStreamBroadcast","stream":{"sessionId":"s1","encryptedText":"\#(sealed.ciphertext)","iv":"\#(sealed.iv)","seq":2,"done":false}}"#)
        await assertEventually { await client.currentSnapshot().liveText["s1"] == "Estou a escrever" }
        box.sockets[0].push(#"{"type":"sessionStreamBroadcast","stream":{"sessionId":"s1","encryptedText":"","iv":"","seq":3,"done":true}}"#)
        await assertEventually { await client.currentSnapshot().liveText["s1"] == nil }
        await client.stop()
    }
}
