import SwiftUI
import UIKit
import AxyomRemoteCore

/// Thin glue between the iOS app and `AxyomRemoteCore`. Anything that can be
/// tested without an iPhone lives in the core; this only holds state for views.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var pairing: PairingPayload?
    @Published private(set) var snapshot = RemoteClient.Snapshot()
    @Published var pairingError: String?

    private(set) var client: RemoteClient?

    init() {
        if let saved = PairingKeychain.load() { connect(saved) }
    }

    var pcStatus: PCStatus { PCStatus.from(devices: snapshot.devices) }

    var desktopDeviceId: String? {
        snapshot.devices.first { $0.type == "desktop" && $0.isOnline == true }?.deviceId
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
        } catch {
            pairingError = "Este código não é válido ou já expirou. Gera outro no PC."
        }
    }

    func unpair() {
        let old = client
        client = nil
        Task { await old?.stop() }
        PairingKeychain.delete()
        pairing = nil
        snapshot = RemoteClient.Snapshot()
    }

    private func connect(_ payload: PairingPayload) {
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
                Task { @MainActor in self?.snapshot = snap }
            }
            await remote.start()
        }
    }
}
