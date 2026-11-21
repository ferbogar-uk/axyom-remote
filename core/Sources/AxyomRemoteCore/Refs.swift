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
    public static func shortenInline(_ text: String, root: String? = nil) -> String {
        var out = linkPCPaths(in: text)
        if let root, !root.isEmpty { out = linkRelativeFiles(in: out, root: root) }
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

    /// The desktop writes `[demo.pdf](C:\\Users\\x\\demo.pdf)`: a Windows path is not a valid link
    /// target, so the label showed as plain text. Turn those (and file:// links) into `axyom-file:` links
    /// so the name in the sentence is tappable, as it is on the PC.
    static func linkPCPaths(in text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(\s*<?([^)\n]+?)>?\s*\)"#) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let label = ns.substring(with: m.range(at: 1))
            var target = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if target.hasPrefix("file:///") {
                target = String(target.dropFirst("file:///".count)).removingPercentEncoding ?? target
                if !target.hasPrefix("/"), !(target.count > 1 && target[target.index(after: target.startIndex)] == ":") { target = "/" + target }
            }
            guard let ref = fileRef(target), ref.target == target || ref.target == target.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)")),
                  target.range(of: #"^([A-Za-z]:[\\/]|/(Users|home|mnt|Volumes)/)"#, options: .regularExpression) != nil else { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += "[\(label)](axyom-file:" + (ref.target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") + ")"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    static let relativeExt = #"(?:pdf|png|jpe?g|gif|webp|heic|md|markdown|txt|json|ya?ml|toml|csv|html?|css|scss|tsx?|jsx?|mjs|cjs|swift|py|rs|go|java|kt|rb|sh|sql|xml|docx?|xlsx?|pptx?)"#

    /// The agent often names a file by its path inside the project ("packages/x/demo.pdf") or only
    /// by its name ("demo.pdf") right next to that path. Make both tappable by joining the project
    /// folder to the path, so the PC can be asked for the full path. A bare name is only linked when
    /// the same reply also gives its path; otherwise there is nothing to join it to.
    static func linkRelativeFiles(in text: String, root: String) -> String {
        let sep = root.contains("\\") ? "\\" : "/"
        let base = root.hasSuffix("/") || root.hasSuffix("\\") ? String(root.dropLast()) : root
        func absolute(_ rel: String) -> String { base + sep + rel.replacingOccurrences(of: "/", with: sep) }
        func link(_ label: String, _ rel: String) -> String {
            "[\(label)](axyom-file:" + (absolute(rel).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") + ")"
        }
        let pathPattern = #"`?(?<![\w/\\:.@-])((?:\.{0,2}/)?(?:[\w.@-]+/)+[\w.@-]+\.\#(relativeExt))(?![\w/\-])`?"#
        guard let pathRe = try? NSRegularExpression(pattern: pathPattern, options: [.caseInsensitive]) else { return text }
        let ns = text as NSString
        var known: [String: String] = [:]          // file name -> relative path
        var out = ""
        var last = 0
        for m in pathRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let before = ns.substring(to: m.range.location)
            if before.hasSuffix("](") || before.hasSuffix("(") && before.dropLast().hasSuffix("]") { continue }
            var rel = ns.substring(with: m.range(at: 1))
            if rel.hasPrefix("./") { rel = String(rel.dropFirst(2)) }
            if rel.hasPrefix("../") { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += link(rel, rel)
            last = m.range.location + m.range.length
            known[(rel as NSString).lastPathComponent] = rel
        }
        out += ns.substring(from: last)
        guard !known.isEmpty else { return text }
        // Bare names, only in the text that is not already a link.
        guard let linkRe = try? NSRegularExpression(pattern: #"\[[^\]\n]*\]\([^)\n]*\)"#) else { return out }
        let o = out as NSString
        var result = ""
        var pos = 0
        func plain(_ chunk: String) -> String {
            var c = chunk
            for (name, rel) in known {
                let pat = #"`?(?<![\w/\\.@-])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\w\-]|/)`?"#
                guard let re = try? NSRegularExpression(pattern: pat) else { continue }
                let cn = c as NSString
                var rebuilt = "", at = 0
                for m in re.matches(in: c, range: NSRange(location: 0, length: cn.length)) {
                    rebuilt += cn.substring(with: NSRange(location: at, length: m.range.location - at))
                    rebuilt += link(name, rel)
                    at = m.range.location + m.range.length
                }
                rebuilt += cn.substring(from: at)
                c = rebuilt
            }
            return c
        }
        for m in linkRe.matches(in: out, range: NSRange(location: 0, length: o.length)) {
            result += plain(o.substring(with: NSRange(location: pos, length: m.range.location - pos)))
            result += o.substring(with: m.range)
            pos = m.range.location + m.range.length
        }
        result += plain(o.substring(from: pos))
        return result
    }

    /// The PC path inside an `axyom-file:` link.
    public static func filePath(from url: URL) -> String? {
        guard url.scheme == "axyom-file" else { return nil }
        return url.absoluteString.dropFirst("axyom-file:".count).removingPercentEncoding
    }
}
