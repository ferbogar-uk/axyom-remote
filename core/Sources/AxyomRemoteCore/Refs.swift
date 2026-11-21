import Foundation

/// Links, files on the PC and pictures mentioned in an agent's reply, shown as
/// cards under the message (tap to open; files show where they are on the PC).
public enum Refs {
    public enum Kind: Equatable, Sendable {
        case web          // a page
        case image        // a picture on the web: shown as a thumbnail
        case file         // a document or folder on the PC
        case pcImage      // a picture or screenshot on the PC
    }

    public struct Ref: Equatable, Sendable, Identifiable {
        public let kind: Kind
        public let target: String     // URL or full path
        public var id: String { target }
        /// Short name: host + path for links, file name for files.
        public var title: String {
            switch kind {
            case .web, .image:
                guard let u = URL(string: target), let host = u.host else { return target }
                let path = u.path == "/" ? "" : u.path
                let short = host.replacingOccurrences(of: "www.", with: "") + path
                return short.count > 48 ? String(short.prefix(48)) + "…" : short
            case .file, .pcImage:
                return target.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? target
            }
        }
        /// The folder on the PC (files only).
        public var folder: String? {
            guard kind == .file || kind == .pcImage else { return nil }
            let parts = target.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            return parts.count > 1 ? parts.dropLast().suffix(2).joined(separator: "/") : nil
        }
    }

    public static let imageExt: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]

    public static func find(_ text: String, limit: Int = 6) -> [Ref] {
        var out: [Ref] = []
        func add(_ r: Ref) { if out.count < limit, !out.contains(where: { $0.target == r.target }) { out.append(r) } }
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        let patterns: [(String, (String) -> Ref?)] = [
            (#"https?://[^\s<>\)\]"'`]+"#, { url in
                let clean = url.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                let ext = (URL(string: clean)?.pathExtension ?? "").lowercased()
                return Ref(kind: imageExt.contains(ext) ? .image : .web, target: clean)
            }),
            // Windows paths with a file extension or a trailing folder: C:\Users\x\file.pdf
            (#"[A-Za-z]:\\(?:[^\\\s<>:"|?*`]+\\)*[^\\\s<>:"|?*`]+\.[A-Za-z0-9]{1,5}"#, fileRef),
            // Unix paths under a home or mount: /Users/x/a.png, /home/x/a.md
            (#"(?<![\w/])/(?:Users|home|mnt|Volumes)/[^\s<>"'`]+\.[A-Za-z0-9]{1,5}"#, fileRef),
        ]
        for (p, make) in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            for m in re.matches(in: text, range: all) {
                if let r = make(ns.substring(with: m.range)) { add(r) }
            }
        }
        return out
    }

    static func fileRef(_ path: String) -> Ref? {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
        let ext = (clean as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return Ref(kind: imageExt.contains(ext) ? .pcImage : .file, target: clean)
    }

    /// Replace bare links and PC paths in a reply with short Markdown links:
    /// "https://github.com/x/y/pull/8" → "[pull/8](…)", "C:\\…\\voz.png" → "[voz.png](axyom-file:…)".
    /// The cards under the message keep the full address.
    public static func shortenInline(_ text: String) -> String {
        var out = text
        for ref in find(text, limit: 20).reversed() {
            let label: String
            let target: String
            switch ref.kind {
            case .web, .image:
                guard let u = URL(string: ref.target) else { continue }
                let parts = u.path.split(separator: "/").suffix(2)
                label = parts.isEmpty ? (u.host ?? ref.target) : parts.joined(separator: "/")
                target = ref.target
            case .file, .pcImage:
                label = ref.title
                target = "axyom-file:" + (ref.target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            }
            // Leave links that are already Markdown ("](" before or "](" wrapping) alone.
            var searchStart = out.startIndex
            var rebuilt = ""
            while let r = out.range(of: ref.target, range: searchStart..<out.endIndex) {
                let before = out[out.startIndex..<r.lowerBound]
                let inMarkdown = before.hasSuffix("](") || before.hasSuffix("[") || before.hasSuffix("<")
                rebuilt += out[searchStart..<r.lowerBound]
                rebuilt += inMarkdown ? String(out[r]) : "[\(label)](\(target))"
                searchStart = r.upperBound
            }
            rebuilt += out[searchStart..<out.endIndex]
            out = rebuilt
        }
        return out
    }

    /// The PC path inside an `axyom-file:` link.
    public static func filePath(from url: URL) -> String? {
        guard url.scheme == "axyom-file" else { return nil }
        return url.absoluteString.dropFirst("axyom-file:".count).removingPercentEncoding
    }
}
