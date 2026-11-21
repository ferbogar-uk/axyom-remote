import Foundation

/// A picture of a file on the PC (request #9): the desktop sends a small JPEG, encrypted
/// with the session key. The spec says "like a message", so accept both shapes: the raw
/// JPEG bytes, or the JPEG as base64 text.
public enum FilePreview {
    public static func image(encryptedImage: String, iv: String, crypto: SyncCrypto) -> Data? {
        guard let plain = try? crypto.decryptData(ciphertext: encryptedImage, iv: iv), !plain.isEmpty else { return nil }
        if isImage(plain) { return plain }
        if let text = String(data: plain, encoding: .utf8) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let b64 = clean.hasPrefix("data:") ? String(clean.drop(while: { $0 != "," }).dropFirst()) : clean
            if let data = Data(base64Encoded: b64), isImage(data) { return data }
        }
        return nil
    }

    static func isImage(_ d: Data) -> Bool {
        let b = [UInt8](d.prefix(4))
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8 { return true }                 // JPEG
        if b.count >= 4, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return true }  // PNG
        return false
    }

    /// Paths the phone can ask the desktop to preview: pictures and PDFs only.
    public static func canPreview(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "pdf" || Refs.imageExt.contains(ext)
    }

    /// A Windows path is written both ways in the wild (`C:\a\b` and `C:/a/b`); the PC may compare
    /// the text exactly, so ask with both. Anything else is asked as it is.
    public static func variants(_ path: String) -> [String] {
        let drive = path.count > 1 && path[path.index(after: path.startIndex)] == ":"
        guard drive else { return [path] }
        let back = path.replacingOccurrences(of: "/", with: "\\")
        let slash = path.replacingOccurrences(of: "\\", with: "/")
        return back == slash ? [back] : [back, slash]
    }

    /// One key for both spellings, so an answer to either fills the same preview.
    public static func normalized(_ path: String) -> String { path.replacingOccurrences(of: "\\", with: "/") }
}
