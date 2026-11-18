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

/// A question the agent asked (AskUserQuestion), waiting for an answer.
public struct PendingQuestion: Equatable, Sendable, Identifiable {
    public struct Option: Equatable, Sendable, Hashable {
        public var label: String
        public var description: String
    }
    public struct Question: Equatable, Sendable, Hashable {
        public var question: String
        public var header: String
        public var options: [Option]
        public var multiSelect: Bool
    }
    public var id: String              // questionId, used to answer
    public var questions: [Question]
}

/// A plan the agent wants approved before it starts editing (ExitPlanMode).
public struct PendingPlan: Equatable, Sendable, Identifiable {
    public var id: String              // requestId, used to answer
    public var summary: String
    public var filePath: String?
}

/// A git commit the agent proposes (developer_git_commit_proposal), waiting for you.
public struct PendingCommit: Equatable, Sendable, Identifiable {
    public var id: String              // proposalId, used to answer
    public var files: [String]
    public var message: String
    public var reasoning: String
}

public enum PendingPrompts {
    /// Commit proposals with no response yet (auto-approved ones are skipped).
    public static func commits(in items: [TranscriptItem]) -> [PendingCommit] {
        var found: [PendingCommit] = []
        var answered: Set<String> = []
        visitAll(items) { object in
            guard let type = object["type"]?.string, let id = object["proposalId"]?.string else { return }
            if type == "git_commit_proposal_response" || type == "git_commit_response" { answered.insert(id); return }
            guard type == "git_commit_proposal" else { return }
            if object["autoApproved"]?.bool == true { answered.insert(id) }
            if let status = object["status"]?.string, status != "pending" { answered.insert(id) }
            guard !found.contains(where: { $0.id == id }) else { return }
            var files: [String] = []
            if case .array(let a)? = object["filesToStage"] { files = a.compactMap { $0.string } }
            found.append(PendingCommit(id: id, files: files, message: object["commitMessage"]?.string ?? "",
                                       reasoning: object["reasoning"]?.string ?? ""))
        }
        return found.filter { !answered.contains($0.id) }
    }

    /// AskUserQuestion requests with no answer yet, oldest first.
    public static func questions(in items: [TranscriptItem]) -> [PendingQuestion] {
        var found: [PendingQuestion] = []
        var answered: Set<String> = []
        visitAll(items) { object in
            guard let type = object["type"]?.string, let id = object["questionId"]?.string else { return }
            if type == "ask_user_question_response" { answered.insert(id); return }
            guard type == "ask_user_question_request" else { return }
            if let status = object["status"]?.string, status != "pending" { answered.insert(id) }
            guard !found.contains(where: { $0.id == id }) else { return }
            var qs: [PendingQuestion.Question] = []
            if case .array(let list)? = object["questions"] {
                for q in list {
                    var opts: [PendingQuestion.Option] = []
                    if case .array(let o)? = q["options"] {
                        opts = o.compactMap { x in x["label"]?.string.map { PendingQuestion.Option(label: $0, description: x["description"]?.string ?? "") } }
                    }
                    qs.append(.init(question: q["question"]?.string ?? "", header: q["header"]?.string ?? "",
                                    options: opts, multiSelect: q["multiSelect"]?.bool ?? false))
                }
            }
            found.append(PendingQuestion(id: id, questions: qs))
        }
        return found.filter { !answered.contains($0.id) }
    }

    /// Plans waiting for approval, oldest first.
    public static func plans(in items: [TranscriptItem]) -> [PendingPlan] {
        var found: [PendingPlan] = []
        var answered: Set<String> = []
        visitAll(items) { object in
            guard let type = object["type"]?.string, let id = object["requestId"]?.string else { return }
            if type == "exit_plan_mode_response" { answered.insert(id); return }
            guard type == "exit_plan_mode_request" else { return }
            if let status = object["status"]?.string, status != "pending" { answered.insert(id) }
            guard !found.contains(where: { $0.id == id }) else { return }
            found.append(PendingPlan(id: id, summary: object["planSummary"]?.string ?? "", filePath: object["planFilePath"]?.string))
        }
        return found.filter { !answered.contains($0.id) }
    }

    private static func visitAll(_ items: [TranscriptItem], _ visit: ([String: JSONValue]) -> Void) {
        for item in items {
            guard let data = item.raw.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
            walk(value, depth: 0, visit)
        }
    }

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