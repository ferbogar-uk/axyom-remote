import WidgetKit
import SwiftUI
import UIKit
import UserNotifications
import AxyomRemoteCore

/// Thin glue between the iOS app and `AxyomRemoteCore`. Anything that can be
/// tested without an iPhone lives in the core; this only holds state for views.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var pairing: PairingPayload?
    @Published private(set) var snapshot = RemoteClient.Snapshot()
    @Published var pairingError: String?
    /// The server's Azure voice (nil until asked, or when the server has none).
    @Published private(set) var voiceStatus: NeuralVoice.Status?
    /// A conversation to open because a notification was tapped.
    @Published var openRequest: String?

    private(set) var client: RemoteClient?
    /// Pictures of PC files the agent mentioned (request #9), by "session|path". This run only.
    /// A file name tapped in a reply: the session screen shows it in a sheet.
    @Published var openFilePath: String?
    /// The PC picked in the switch on the home screen (nil = all PCs). Kept between launches.
    @Published var selectedPC: String? = UserDefaults.standard.string(forKey: "selectedPC") {
        didSet { UserDefaults.standard.set(selectedPC, forKey: "selectedPC") }
    }
    var pcChoices: [PCChoice] { PCSwitch.choices(devices: snapshot.devices, sessions: snapshot.sessions) }
    /// Sessions of the PC in the switch (all of them when none is picked).
    var visibleSessions: [FleetSession] { PCSwitch.filter(snapshot.sessions, device: selectedPC, devices: snapshot.devices) }
    @Published private(set) var filePreviews: [String: Data] = [:]
    /// Asked but not answered yet / gave up waiting (the PC refuses silently for paths it does not allow).
    /// Text of code/text files from the PC (request #15), by the same key.
    @Published private(set) var fileTexts: [String: (text: String, truncated: Bool)] = [:]
    @Published private(set) var previewWaiting: Set<String> = []
    @Published private(set) var previewFailed: Set<String> = []
    static func previewKey(_ sessionId: String, _ path: String) -> String { sessionId + "|" + FilePreview.normalized(path) }

    func requestPreview(sessionId: String, path: String, target: String?) {
        let key = Self.previewKey(sessionId, path)
        guard let client, filePreviews[key] == nil, fileTexts[key] == nil, !previewWaiting.contains(key) else { return }
        previewFailed.remove(key)
        previewWaiting.insert(key)
        Task {
            for variant in FilePreview.variants(path) {
                if FilePreview.canText(path) {
                    try? await client.requestFileText(sessionId: sessionId, path: variant, targetDeviceId: target)
                } else {
                    try? await client.requestFilePreview(sessionId: sessionId, path: variant, targetDeviceId: target)
                }
            }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if filePreviews[key] == nil, fileTexts[key] == nil { previewWaiting.remove(key); previewFailed.insert(key) }
        }
    }
    /// Last sessions and conversations, kept on the phone for offline viewing.
    let cache = OfflineCache(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("axyom-cache", isDirectory: true))
    /// Images you sent, by session and message text, to show as thumbnails (this run of the app).
    var sentImages: [String: [Data]] = [:]
    private var attention = AttentionWatcher()
    private var finishes = FinishWatcher()

    init() {
        let bridge = PushBridge.shared
        bridge.onToken = { [weak self] token in self?.sendPushToken(token) }
        bridge.onOpen = { [weak self] id in self?.openRequest = id }
        bridge.onAnswer = { [weak self] id, allow in await self?.answerFromNotification(sessionId: id, allow: allow) }
        if let pending = bridge.pendingOpen { openRequest = pending; bridge.pendingOpen = nil }
        if DemoData.isOn { startDemo(); return }
        if let saved = PairingKeychain.load() { connect(saved) }
    }

    /// Screenshots in the simulator: example data, no network.
    @Published private(set) var isDemo = false
    private func startDemo() {
        isDemo = true
        pairing = DemoData.pairing
        snapshot = DemoData.snapshot()
        switch DemoData.screen {
        case "session": openRequest = DemoData.mainSession
        case "voice": openRequest = "talk:" + DemoData.mainSession
        default: break
        }
    }

    /// Push to this phone with the app closed: "a registar", "ativo", "servidor sem chave", "recusado".
    var pushStatus: String {
        if PushBridge.shared.failed { return "iPhone recusou" }
        switch snapshot.pushReady {
        case true?: return "ativo"
        case false?: return "servidor sem chave"
        case nil: return PushBridge.shared.token == nil ? "por ativar" : "a registar"
        }
    }

    /// Ask the server whether it has the Azure voice; ReplySpeaker uses it only then.
    func refreshVoice() async {
        guard let pairing, let request = NeuralVoice.statusRequest(pairing: pairing) else { return }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let status = try? JSONDecoder().decode(NeuralVoice.Status.self, from: data) else {
            voiceStatus = nil
            ReplySpeaker.neural = nil
            SpeechListener.azureSTT = nil
            return
        }
        voiceStatus = status
        SpeechListener.azureSTT = status.configured && status.stt ? { wav, language in
            guard var request = NeuralVoice.sttRequest(pairing: pairing, wav: wav, language: language) else { return nil }
            request.timeoutInterval = 8      // a slow answer falls back to Apple's text
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NeuralVoice.sttText(data)
        } : nil
        guard status.configured, !status.exhausted else { ReplySpeaker.neural = nil; return }
        ReplySpeaker.neural = { text in
            let voice = Prefs.azureVoice
            guard let request = NeuralVoice.ttsRequest(pairing: pairing, text: text, voice: voice.isEmpty ? nil : voice,
                                                       rateMultiplier: Double(Prefs.speechRateMultiplier)),
                  let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
            return data
        }
    }

    /// What each waiting session asks (home cards), and whether Permitir is safe there.
    @Published private(set) var pendingRequests: [String: (text: String, canAllow: Bool)] = [:]

    func loadPendingRequests(_ sessions: [FleetSession]) async {
        if isDemo {
            for s in sessions { pendingRequests[s.id] = ("Quer correr: git push origin main", true) }
            return
        }
        guard let client else { return }
        for s in sessions {
            guard let items = try? await client.loadTranscript(sessionId: s.id) else { continue }
            pendingRequests[s.id] = Self.describePending(items)
        }
    }

    static func describePending(_ items: [TranscriptItem]) -> (text: String, canAllow: Bool) {
        if let q = PendingPrompts.questions(in: items).last { return ("Pergunta: " + (q.questions.first?.question ?? "responde na app"), false) }
        if PendingPrompts.plans(in: items).last != nil { return ("Quer aprovação de um plano.", false) }
        if let c = PendingPrompts.commits(in: items).last { return ("Propõe um commit: " + c.message, false) }
        let perms = PendingPrompts.permissions(in: items)
        guard let p = perms.last else { return ("Abre para ver o pedido.", false) }
        let canAllow: Bool
        if case .answer = NotificationAnswer.decide(items, allow: true) { canAllow = true } else { canAllow = false }
        return ((p.isDestructive ? "Pedido destrutivo: " : "Quer correr: ") + NotificationAnswer.describe(p), canAllow)
    }

    /// Permitir on a home card: same rules as the notification button.
    func allowFromHome(_ s: FleetSession) async {
        guard let client, !isDemo else { return }
        _ = await client.answerFromNotification(sessionId: s.id, allow: true)
        pendingRequests[s.id] = nil
        Prefs.tap()
    }

    /// Permitir / Recusar tapped on a notification: answer the single pending
    /// permission, then confirm with a quiet local notification.
    func answerFromNotification(sessionId: String, allow: Bool) async {
        if client == nil, let saved = PairingKeychain.load() { connect(saved) }
        guard let client else { return }
        let outcome = await client.answerFromNotification(sessionId: sessionId, allow: allow)
        let content = UNMutableNotificationContent()
        content.threadIdentifier = sessionId
        content.userInfo = ["sessionId": sessionId]
        switch outcome {
        case .answered(let allowed, let what):
            content.title = allowed ? "Permitido" : "Recusado"
            content.body = what
        case .openApp(let reason):
            content.title = "Abre a app para responder"
            content.body = reason
            content.sound = .default
        case .nothingPending:
            content.title = "Já não há nada à espera"
            content.body = "O pedido já foi respondido."
        case .offline:
            content.title = "Não consegui responder"
            content.body = "O PC não respondeu. Abre a app para tentar outra vez."
            content.sound = .default
        }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "answer-\(sessionId)", content: content, trigger: nil))
        Prefs.tap()
    }

    private func sendPushToken(_ token: String) {
        #if DEBUG
        let development = true
        #else
        let development = false
        #endif
        guard let client else { return }
        Task { await client.setPushToken(token, development: development) }
    }

    var pcStatus: PCStatus { PCStatus.from(devices: snapshot.devices) }

    var desktopDeviceId: String? {
        snapshot.devices.first { $0.type == "desktop" && $0.isOnline == true }?.deviceId
    }

    /// The online PC that holds this project (by its encrypted id), else any online PC.
    func desktopId(forEncryptedProjectId encrypted: String?) -> String? {
        DesktopRouting.desktop(forEncryptedProjectId: encrypted, devices: snapshot.devices, preferred: selectedPC)?.deviceId
    }

    func board(project: String? = nil) -> FleetBoard {
        FleetBoard.build(visibleSessions, project: project)
    }

    // MARK: Pairing

    func pair(code: String) {
        do {
            let payload = try PairingPayload.parse(code.trimmingCharacters(in: .whitespacesAndNewlines))
            try PairingKeychain.save(payload)
            pairingError = nil
            connect(payload)
        } catch PairingPayload.ParseError.notAxyomCode {
            pairingError = "Este código não é do AXYOM Remote. O QR do ecrã de Sincronização do PC é o formato antigo do Nimbalyst; o PC ainda tem de mostrar o código novo (axyom-pair)."
        } catch PairingPayload.ParseError.expired {
            pairingError = "Este código já expirou. Gera outro no PC."
        } catch {
            pairingError = "Este código não é válido. Gera outro no PC."
        }
    }

    func unpair() {
        let old = client
        client = nil
        LiveActivities.shared.endAll()
        Task { await old?.clearPushToken(); await old?.stop() }
        PairingKeychain.delete()
        cache.clear()
        ReplySpeaker.neural = nil
        SpeechListener.azureSTT = nil
        SharedKeychain.clear()
        lastPushContext = nil
        voiceStatus = nil
        pairing = nil
        snapshot = RemoteClient.Snapshot()
    }

    private func apply(_ snap: RemoteClient.Snapshot) {
        snapshot = snap
        sharePushContext(snap.sessions)
        shareWidget(snap)
        LiveActivities.shared.follow(snap.sessions)
        checkLimits(snap.planUsage)
        for s in attention.update(snap.sessions) { notifyWaiting(s) }
        for s in finishes.update(snap.sessions) { notifyFinished(s) }
    }

    /// Local notification when an agent finishes its turn (same limits as the waiting one).
    /// A plan window crossed 80 %: one local alert per window and reset.
    /// Works while the app is open or recently in the background.
    private func checkLimits(_ usage: [PlanUsage]) {
        guard Prefs.notifyLimit, let latest = usage.first else { return }
        let iso = ISO8601DateFormatter()
        for plan in latest.plans {
            for w in plan.windows where w.percent >= UsagePace.criticalPercent {
                let key = "limit|\(plan.id)|\(w.name)|\(w.resetsAt ?? "")"
                guard !UserDefaults.standard.bool(forKey: key) else { continue }
                UserDefaults.standard.set(true, forKey: key)
                let content = UNMutableNotificationContent()
                content.title = "\(plan.label) a \(Int(w.percent.rounded()))%"
                let window = UsagePace.duration(of: w.name)?.label ?? w.name
                var body = "Janela de \(window) quase no limite. O agente pode parar."
                if let r = w.resetsAt, let d = iso.date(from: r) {
                    let h = Int(max(0, d.timeIntervalSinceNow) / 3600), m = Int(max(0, d.timeIntervalSinceNow).truncatingRemainder(dividingBy: 3600) / 60)
                    body += h > 0 ? " Renova em \(h)h \(m)min." : " Renova em \(m)min."
                }
                content.body = body
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
            }
        }
    }

    /// A prompt just went to this session from the phone: show it in the Dynamic Island.
    func sessionPrompted(_ sessionId: String) {
        guard let s = snapshot.sessions.first(where: { $0.id == sessionId }) else {
            UserDefaults.standard.set("Sessão não encontrada na lista ao enviar.", forKey: "liveActivityResult")
            return
        }
        LiveActivities.shared.start(for: s, waitingCount: snapshot.sessions.filter { $0.hasPendingPrompt && !$0.isArchived }.count)
    }

    /// The home-screen widget's data, rewritten (and the widget reloaded) only when it changes.
    private var lastWidget: WidgetSnapshot?
    private func shareWidget(_ snap: RemoteClient.Snapshot) {
        let w = WidgetSnapshot.make(sessions: snap.sessions, usage: snap.planUsage, pc: PCStatus.from(devices: snap.devices))
        guard !(lastWidget.map { $0.sameContent(as: w) } ?? false) else { return }
        lastWidget = w
        SharedKeychain.saveWidget(w)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Session titles for the notification extension, rewritten only when they change.
    private var lastPushContext: PushContent.Context?
    private func sharePushContext(_ sessions: [FleetSession]) {
        let ctx = PushContent.context(from: sessions, seed: pairing?.seed, member: pairing?.member)
        guard ctx != lastPushContext else { return }
        lastPushContext = ctx
        SharedKeychain.save(ctx)
    }

    private func localContent(_ s: FleetSession, kind: String) -> UNMutableNotificationContent {
        let text = PushContent.compose(kind: kind, entry: .init(title: s.title, provider: s.provider, project: s.projectName))
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.subtitle = text.subtitle
        content.body = text.body
        content.threadIdentifier = s.id
        if kind == "waiting" { content.categoryIdentifier = PushCategory.waiting }
        return content
    }

    private func notifyFinished(_ s: FleetSession) {
        guard Prefs.notifyFinished, UIApplication.shared.applicationState != .active else { return }
        let content = localContent(s, kind: "finished")
        content.sound = .default
        content.userInfo = ["sessionId": s.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "done-\(s.id)-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil))
    }

    /// Local notification when a session starts waiting for you. It only fires
    /// while the app is running (open or recently in the background): iOS
    /// suspends the connection soon after. With the app closed the server sends an APNs push instead.
    private func notifyWaiting(_ s: FleetSession) {
        guard Prefs.notifications, UIApplication.shared.applicationState != .active else { return }
        let content = localContent(s, kind: "waiting")
        content.sound = .default
        content.userInfo = ["sessionId": s.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "wait-\(s.id)", content: content, trigger: nil))
    }

    private func askNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    private func connect(_ payload: PairingPayload) {
        askNotificationPermission()
        guard let crypto = try? SyncCrypto(seed: payload.seed, memberId: payload.member) else {
            pairingError = "Não consegui preparar a cifra com este código."
            return
        }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let device = DeviceInfo(
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            name: UIDevice.current.name,
            type: "mobile",
            platform: "ios",
            appVersion: "0.1.0",
            connectedAt: nowMs,
            lastActiveAt: nowMs
        )
        let remote = RemoteClient(pairing: payload, crypto: crypto, device: device, factory: URLSessionSyncSocket.factory)
        client = remote
        LiveActivities.shared.client = remote
        pairing = payload
        Task {
            await remote.setOnChange { [weak self] snap in
                Task { @MainActor in self?.apply(snap) }
            }
            await remote.setFilePreviewHandler { [weak self] sid, path, jpeg in
                Task { @MainActor in
                    guard let self else { return }
                    let key = Self.previewKey(sid, path)
                    self.filePreviews[key] = jpeg
                    self.previewWaiting.remove(key); self.previewFailed.remove(key)
                }
            }
            await remote.setFileTextHandler { [weak self] sid, path, text, truncated in
                Task { @MainActor in
                    guard let self else { return }
                    let key = Self.previewKey(sid, path)
                    self.fileTexts[key] = (text, truncated)
                    self.previewWaiting.remove(key); self.previewFailed.remove(key)
                }
            }
            await remote.useCache(cache)
            await remote.start()
            if let token = PushBridge.shared.token { await MainActor.run { self.sendPushToken(token) } }
            await self.refreshVoice()
        }
    }
}
