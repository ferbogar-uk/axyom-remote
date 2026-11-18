import SwiftUI
import UIKit
import UserNotifications
import AxyomRemoteCore

/// Thin glue between the iOS app and `AxyomRemoteCore`. Anything that can be
/// tested without an iPhone lives in the core; this only holds state for views.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var pairing: PairingPayload?
    @Published private(set) var snapshot = RemoteClient.Snapshot()
    @Published var pairingError: String?

    private(set) var client: RemoteClient?
    /// Last sessions and conversations, kept on the phone for offline viewing.
    let cache = OfflineCache(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("axyom-cache", isDirectory: true))
    /// Images you sent, by session and message text, to show as thumbnails (this run of the app).
    var sentImages: [String: [Data]] = [:]
    private var attention = AttentionWatcher()

    init() {
        if let saved = PairingKeychain.load() { connect(saved) }
    }

    var pcStatus: PCStatus { PCStatus.from(devices: snapshot.devices) }

    var desktopDeviceId: String? {
        snapshot.devices.first { $0.type == "desktop" && $0.isOnline == true }?.deviceId
    }

    /// The online PC that holds this project (by its encrypted id), else any online PC.
    func desktopId(forEncryptedProjectId encrypted: String?) -> String? {
        DesktopRouting.desktop(forEncryptedProjectId: encrypted, devices: snapshot.devices)?.deviceId
    }

    func board(project: String? = nil) -> FleetBoard {
        FleetBoard.build(snapshot.sessions, project: project)
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
        Task { await old?.stop() }
        PairingKeychain.delete()
        cache.clear()
        pairing = nil
        snapshot = RemoteClient.Snapshot()
    }

    private func apply(_ snap: RemoteClient.Snapshot) {
        snapshot = snap
        for s in attention.update(snap.sessions) { notifyWaiting(s) }
    }

    /// Local notification when a session starts waiting for you. It only fires
    /// while the app is running (open or recently in the background): iOS
    /// suspends the connection soon after. Real push needs the server (docs/REQUESTS-TO-DESKTOP.md).
    private func notifyWaiting(_ s: FleetSession) {
        guard Prefs.notifications, UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "À espera de ti"
        content.body = "\(s.title) · \(s.projectName)"
        content.sound = .default
        content.userInfo = ["sessionId": s.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "wait-\(s.id)", content: content, trigger: nil))
    }

    private func askNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
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
        pairing = payload
        Task {
            await remote.setOnChange { [weak self] snap in
                Task { @MainActor in self?.apply(snap) }
            }
            await remote.useCache(cache)
            await remote.start()
        }
    }
}
