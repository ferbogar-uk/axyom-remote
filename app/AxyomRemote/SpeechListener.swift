import Foundation
import AVFoundation
import Speech

/// Listens in Portuguese (Brazilian first, then European). Uses Apple's
/// on-device recognizer when the iPhone has the language downloaded; otherwise
/// it uses Apple's speech servers and says so on screen (`onDevice == false`).
@MainActor
final class SpeechListener: ObservableObject {
    @Published var transcript = ""
    @Published var listening = false
    @Published var problem: String?
    /// Whether the last recognition ran on the iPhone (false = Apple's servers).
    @Published var onDevice = true

    private var recognizer: SFSpeechRecognizer?

    /// Portuguese recognizer: on-device if any variant supports it, else the first available one.
    private static func pickRecognizer() -> SFSpeechRecognizer? {
        let ids = ["pt-BR", "pt-PT"]
        let all = ids.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
        return all.first { $0.isAvailable && $0.supportsOnDeviceRecognition } ?? all.first { $0.isAvailable } ?? all.first
    }
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var autoStop = false
    /// Seconds of silence after speech that end listening when auto-stop is on.
    var silenceSeconds: TimeInterval = 1.8

    func toggle(autoStop: Bool = false) {
        if listening { stop() } else { self.autoStop = autoStop; start() }
    }

    func start() {
        problem = nil
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.problem = "Sem permissão de reconhecimento de voz. Ativa-a nas Definições do iPhone."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted { self.begin() } else { self.problem = "Sem permissão para usar o microfone. Ativa-a nas Definições do iPhone." }
                    }
                }
            }
        }
    }

    private func begin() {
        recognizer = Self.pickRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            problem = "O reconhecimento de voz não está disponível agora. Confirma a ligação à internet."
            return
        }
        onDevice = recognizer.supportsOnDeviceRecognition
        do {
            let audio = AVAudioSession.sharedInstance()
            // playAndRecord so the same session can read the agent's reply aloud afterwards.
            try audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = onDevice
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let text = result?.bestTranscription.formattedString {
                        self.transcript = text
                        self.armSilenceTimer()
                    }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
            listening = true
        } catch {
            problem = "Não consegui ligar o microfone."
            stop()
        }
    }

    private func armSilenceTimer() {
        guard autoStop, listening else { return }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        guard listening || engine.isRunning else { return }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
    }
}
