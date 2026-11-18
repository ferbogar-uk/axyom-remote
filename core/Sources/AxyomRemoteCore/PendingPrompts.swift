import Foundation

/// A tool-permission question the PC is waiting on (read from the transcript).
public struct PendingPermission: Equatable, Sendable, Identifiable {
    public var id: String              // requestId, used to answer
    public var toolName: String
    public var rawCommand: String      // what the agent wants to run
    public var patternDisplayName: String
    public var isDestructive: Bool
    public var warnings: [String]
}

public enum PendingPrompts {
    /// Permission requests with no answer yet, oldest first. A request is
    /// answered when a `permission_response` with the same id exists, or when
    /// its own status says it is no longer pending.
    public static func permissions(in items: [TranscriptItem]) -> [PendingPermission] {
        var requests: [PendingPermission] = []
        var answered: Set<String> = []
        for item in items {
            guard let data = item.raw.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
            walk(value, depth: 0) { object in
                guard let type = object["type"]?.string else { return }
                if type == "permission_response", let id = object["requestId"]?.string {
                    answered.insert(id)
                } else if type == "permission_request", let id = object["requestId"]?.string {
                    if let status = object["status"]?.string, status != "pending" { answered.insert(id) }
                    guard !requests.contains(where: { $0.id == id }) else { return }
                    requests.append(PendingPermission(
                        id: id,
                        toolName: object["toolName"]?.string ?? "",
                        rawCommand: object["rawCommand"]?.string ?? "",
                        patternDisplayName: object["patternDisplayName"]?.string ?? "",
                        isDestructive: object["isDestructive"]?.bool ?? false,
                        warnings: Self.strings(object["warnings"])
                    ))
                }
            }
        }
        return requests.filter { !answered.contains($0.id) }
    }

    private static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let a)? = value else { return [] }
        return a.compactMap { $0.string }
    }

    private static func walk(_ v: JSONValue, depth: Int, _ visit: ([String: JSONValue]) -> Void) {
        guard depth < 6 else { return }
        switch v {
        case .object(let o):
            visit(o)
            for x in o.values { walk(x, depth: depth + 1, visit) }
        case .array(let a):
            for x in a { walk(x, depth: depth + 1, visit) }
        case .string(let s) where depth > 0 && s.hasPrefix("{"):
            if let d = s.data(using: .utf8), let inner = try? JSONDecoder().decode(JSONValue.self, from: d) {
                walk(inner, depth: depth + 1, visit)
            }
        default:
            break
        }
    }
}