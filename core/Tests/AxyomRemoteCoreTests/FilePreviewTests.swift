import XCTest
@testable import AxyomRemoteCore

final class FilePreviewTests: XCTestCase {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4])

    func crypto() throws -> SyncCrypto { try SyncCrypto(seed: "seed", memberId: "owner") }

    func testDecodesRawJPEGBytes() throws {
        let c = try crypto(); let s = try c.encryptData(jpeg)
        XCTAssertEqual(FilePreview.image(encryptedImage: s.ciphertext, iv: s.iv, crypto: c), jpeg)
    }

    func testDecodesBase64Text() throws {
        let c = try crypto(); let s = try c.encrypt(jpeg.base64EncodedString())
        XCTAssertEqual(FilePreview.image(encryptedImage: s.ciphertext, iv: s.iv, crypto: c), jpeg)
    }

    func testRejectsGarbageAndWrongKey() throws {
        let c = try crypto(); let s = try c.encrypt("not a picture")
        XCTAssertNil(FilePreview.image(encryptedImage: s.ciphertext, iv: s.iv, crypto: c))
        let other = try SyncCrypto(seed: "other", memberId: "owner")
        let t = try c.encryptData(jpeg)
        XCTAssertNil(FilePreview.image(encryptedImage: t.ciphertext, iv: t.iv, crypto: other))
    }

    func testFrameDecodesAndRequestEncodes() throws {
        let m = try ServerMessage.decode(#"{"type":"filePreview","path":"C:\\a\\b.png","encryptedImage":"x","iv":"y"}"#)
        XCTAssertEqual(m, .filePreview(path: "C:\\a\\b.png", encryptedImage: "x", iv: "y"))
    }

    func testOnlyPicturesAndPDFs() {
        XCTAssertTrue(FilePreview.canPreview("C:\\x\\shot.PNG"))
        XCTAssertTrue(FilePreview.canPreview("/home/a/plan.pdf"))
        XCTAssertFalse(FilePreview.canPreview("/home/a/notes.md"))
    }

    func testWorktreeFromMetadata() throws {
        let c = try crypto()
        let meta = try c.encrypt(#"{"worktreeName":"azure-listen","branch":"feat/x","worktreePath":"C:\\w"}"#)
        let t = try c.encrypt("Titulo")
        let p = try c.encrypt("/p/AXYOM")
        var e = SessionIndexEntry(sessionId: "s1", encryptedProjectId: p.ciphertext, projectIdIv: p.iv, encryptedTitle: t.ciphertext, titleIv: t.iv,
                                  provider: "claude-code", hostDeviceId: "pc1", lastMessageAt: 1000, createdAt: 1, updatedAt: 2)
        e.encryptedClientMetadata = meta.ciphertext; e.clientMetadataIv = meta.iv
        let s = FleetSession.from(e, crypto: c)
        XCTAssertEqual(s?.worktreeName, "azure-listen")
        XCTAssertEqual(s?.branch, "feat/x")
    }

    func testWindowsPathsAreAskedBothWays() {
        XCTAssertEqual(FilePreview.variants("C:/Users/r/a b/x.pdf"), ["C:\\Users\\r\\a b\\x.pdf", "C:/Users/r/a b/x.pdf"])
        XCTAssertEqual(FilePreview.variants("/home/r/x.pdf"), ["/home/r/x.pdf"])
        XCTAssertEqual(FilePreview.normalized("C:\\a\\b.pdf"), "C:/a/b.pdf")
    }

    func testFileTextFrameAndDecrypt() throws {
        let m = try ServerMessage.decode(#"{"type":"fileText","path":"C:\\a\\x.md","encryptedText":"x","iv":"y","truncated":true}"#)
        XCTAssertEqual(m, .fileText(path: "C:\\a\\x.md", encryptedText: "x", iv: "y", truncated: true))
        let c = try crypto(); let e = try c.encrypt("# Titulo\nolá")
        XCTAssertEqual(FilePreview.text(encryptedText: e.ciphertext, iv: e.iv, crypto: c), "# Titulo\nolá")
    }

    func testWhichFilesAreText() {
        XCTAssertTrue(FilePreview.canText("/p/src/App.TSX"))
        XCTAssertTrue(FilePreview.canText(#"C:\p\README"#))
        XCTAssertFalse(FilePreview.canText("/p/photo.png"))
        XCTAssertFalse(FilePreview.canText("/p/plan.pdf"))
    }
}
