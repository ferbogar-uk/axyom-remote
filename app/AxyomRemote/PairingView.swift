import SwiftUI
import AVFoundation
import AxyomRemoteCore

/// First screen: scan the QR the desktop shows, or paste the code.
struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var attempt = 0
    @State private var pasting = false
    @State private var pasted = ""
    @State private var cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Image("AxyomLockup").resizable().scaledToFit().frame(height: 44).accessibilityLabel("AXYOM")
                Text("Ligar ao teu PC").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                Text("No AXYOM do PC, abre o ecrã de emparelhamento e aponta a câmara ao código.")
                    .font(.body).foregroundStyle(Theme.textSoft)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface)
                if cameraDenied {
                    Text("A câmara está desligada para esta app. Ativa-a nas Definições do iPhone ou cola o código.")
                        .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(24)
                } else {
                    QRScannerView { code in
                        model.pair(code: code)
                        if model.pairingError != nil { attempt += 1 }
                    }
                    .id(attempt)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .accessibilityLabel("Área da câmara para ler o código QR")

            if let error = model.pairingError { Text(error).font(.subheadline).foregroundStyle(Theme.danger) }
            Text("O código vale 10 minutos. Se expirar, gera outro no PC.").font(.footnote).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button("Colar o código em vez de ler") { pasting = true }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
        .sheet(isPresented: $pasting) { pasteSheet }
    }

    private var pasteSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colar o código").font(.title3.bold()).foregroundStyle(Theme.text)
            TextEditor(text: $pasted)
                .scrollContentBackground(.hidden).foregroundStyle(Theme.text)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(10).frame(height: 140)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
            if let error = model.pairingError { Text(error).font(.subheadline).foregroundStyle(Theme.danger) }
            Button("Ligar") {
                model.pair(code: pasted)
                if model.pairingError == nil { pasting = false }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.surface)
        .presentationDetents([.medium])
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { if granted { self.configure() } }
            }
        default: break
        }
    }

    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished,
              let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        finished = true
        onCode?(text)
    }
}
