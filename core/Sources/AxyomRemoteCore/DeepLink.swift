import Foundation

/// Links the widget (and later the Live Activity) use to open the app on a screen:
/// `axyom://session/<id>` opens that conversation, `axyom://home` the session list.
public enum DeepLink: Equatable, Sendable {
    case home
    case session(String)

    public static let scheme = "axyom"

    public var url: URL {
        switch self {
        case .home: return URL(string: "axyom://home")!
        case .session(let id):
            let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
            return URL(string: "axyom://session/\(safe)")!
        }
    }

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host?.lowercased() {
        case "home": self = .home
        case "session":
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).removingPercentEncoding ?? ""
            guard !id.isEmpty else { return nil }
            self = .session(id)
        default: return nil
        }
    }
}
