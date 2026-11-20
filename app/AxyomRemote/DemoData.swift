import Foundation
import AxyomRemoteCore

/// Demo mode (launch argument `-AXYOMDemo`): example sessions, usage and a
/// conversation, so the simulator can take screenshots of every screen without
/// a paired PC. Never used in normal launches.
/// `-AXYOMScreen home|session|voice|settings` picks the screen to open.
enum DemoData {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-AXYOMDemo") }
    static var screen: String {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-AXYOMScreen"), i + 1 < a.count else { return "home" }
        return a[i + 1]
    }

    static let pairing = PairingPayload(server: "https://demo.invalid", key: "demo", seed: "demo", issuedAt: 0)
    static let project = #"C:\Users\ricar\PROJECTS\AXYOM - AI Development OS"#
    static let mainSession = "demo-aion"

    static func snapshot(now: Date = Date()) -> RemoteClient.Snapshot {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func s(_ id: String, _ title: String, _ provider: String, _ min: Double, parent: String? = nil,
               role: String? = nil, phase: String? = nil, working: Bool = false, waiting: Bool = false, unread: Bool = false) -> FleetSession {
            var x = FleetSession(id: id, title: title, projectId: project, provider: provider, isExecuting: working,
                                 hasPendingPrompt: waiting, hostDeviceId: "pc", lastActivity: ago(min),
                                 lastReadAt: unread ? ago(min + 5) : ago(min - 1), lastMessageAt: ago(min))
            x.parentId = parent; x.agentRole = role; x.phase = phase
            return x
        }
        var snap = RemoteClient.Snapshot()
        snap.connected = true
        snap.sessions = [
            s("demo-orch", "Oi. Aqui, pelo amor de Deus…", "openai-codex", 6, role: "meta-agent"),
            s(mainSession, "01 Aion | AXYOM Development", "claude-code", 6, parent: "demo-orch", phase: "implementing", working: true),
            s("demo-sub1", "Oi", "openai-codex", 60 * 24, parent: mainSession),
            s("demo-sub2", "New Sub-agent", "gemini", 60 * 48, parent: mainSession),
            s("demo-wait", "Corrigir login no site", "claude-code", 12, waiting: true),
            s("demo-plan", "Análise do repositório", "claude-code", 60 * 22, phase: "planning"),
            s("demo-grok", "Teste do AXYOM: responde apenas OK", "grok-build", 60 * 26),
            s("demo-cursor", "Teste do AXYOM: Cursor", "cursor-agent", 60 * 50, unread: true),
        ]
        var pc = DeviceInfo(deviceId: "pc", name: "Home Laptop", type: "desktop", platform: "win32",
                            connectedAt: now.timeIntervalSince1970 * 1000, lastActiveAt: now.timeIntervalSince1970 * 1000, status: "online")
        pc.isOnline = true
        snap.devices = [pc]
        let iso = ISO8601DateFormatter()
        func reset(_ s: TimeInterval) -> String { iso.string(from: now.addingTimeInterval(s)) }
        let usage = """
        {"desktopName":"Home Laptop","updatedAt":\(now.timeIntervalSince1970 * 1000),
         "plans":[{"id":"claude","label":"Claude","percent":49,"windows":[
                     {"name":"Session","percent":49,"resetsAt":"\(reset(2.6 * 3600))"},
                     {"name":"Weekly","percent":31,"resetsAt":"\(reset(5 * 86400 + 17 * 3600))"},
                     {"name":"Fable (Weekly)","percent":0,"resetsAt":"\(reset(5 * 86400 + 17 * 3600))"}]},
                  {"id":"codex","label":"Codex","percent":4,"windows":[{"name":"Weekly","percent":4,"resetsAt":"\(reset(6 * 86400 + 17 * 3600))"}]},
                  {"id":"grok","label":"Grok","percent":84,"windows":[{"name":"Session","percent":84,"resetsAt":"\(reset(1.2 * 3600))"}]},
                  {"id":"oc","label":"OC Go","percent":22,"windows":[]}],
         "models":[{"id":"sonnet-5.5","name":"Sonnet 5.5","provider":"claude-code","efforts":["low","medium","high"]}],
         "defaultEffort":"low"}
        """
        if var u = try? JSONDecoder().decode(PlanUsage.self, from: Data(usage.utf8)) { u.deviceId = "pc"; snap.planUsage = [u] }
        return snap
    }

    static func transcript() -> [TranscriptItem] {
        var n = 0
        func row(_ raw: String, _ dir: String = "output") -> TranscriptItem {
            n += 1
            return TranscriptItem(id: "d\(n)", sequence: n, createdAt: Date(), source: "demo", direction: dir, hidden: false,
                                  raw: raw, text: TranscriptText.readable(raw))
        }
        return [
            row("Explica em três frases o que é o AXYOM.", "input"),
            row(#"{"type":"assistant","message":{"content":[{"type":"text","text":"O AXYOM é um espaço de trabalho de IA que corre no teu PC e junta vários agentes (Claude, Codex, Gemini) no mesmo sítio.\n\nCada sessão tem a sua conversa, os seus ficheiros e, quando é preciso, o seu próprio worktree.\n\nO **AXYOM Remote** deixa-te acompanhar e responder a tudo isto a partir do iPhone."}]}}"#),
            row("Muda a velocidade da voz para ser configurável.", "input"),
            row(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"C:\\AXYOM\\app\\ReplySpeaker.swift"}}]}}"#),
            row(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"C:\\AXYOM\\app\\ReplySpeaker.swift","old_string":"let a = 1\nlet rate = 1.0\nlet b = 2","new_string":"let a = 1\nlet rate = Prefs.speed\nlet b = 2"}}]}}"#),
            row(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"pnpm vitest run","description":"Run tests"}}]}}"#),
            row(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Feito. A velocidade passa a vir das Definições.\n\n```swift\nlet rate = Prefs.speed\nutterance.rate = rate\n```\n\nVê o resumo em https://github.com/ferbogar-uk/axyom-remote/pull/8 e o print em C:\\Users\\ricar\\Pictures\\voz.png"}]}}"#),
        ]
    }
}
