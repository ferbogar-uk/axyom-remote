import Foundation
import AVFoundation
import Speech
import AxyomRemoteCore

/// Listens in Portuguese (Brazilian first, then European). Uses Apple's
/// on-device recognizer when the iPhone has the language downloaded; otherwise
/// it uses Apple's speech servers and says so on screen (`onDevice == false`).
///
/// A pause makes iOS start a new phrase (or end the recognition task). The text
/// already heard is kept and the new phrase is added after it (TranscriptJoiner),
/// and a finished task is restarted while the user is still talking, so a pause
/// never wipes what was said.
@MainActor
final class SpeechListener: ObservableObject {
    @Published var transcript = ""
    @Published var listening = false
    @Published var problem: String?
    /// Whether the last recognition ran on the iPhone (false = Apple's servers).
    @Published var onDevice = true

    private var recognizer: SFSpeechRecognizer?
    private var joiner = TranscriptJoiner()

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
    /// 2.5 s, the value AVA settled on: shorter cut people off mid-thought.
    var silenceSeconds: TimeInterval = 2.5

    func toggle(autoStop: Bool = false) {
        if listening { stop() } else { self.autoStop = autoStop; start() }
    }

    func start() {
        problem = nil
        transcript = ""
        joiner = TranscriptJoiner()
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
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                // The current request changes when a task is restarted after a pause.
                Task { @MainActor in self?.request?.append(buffer) }
            }
            engine.prepare()
            try engine.start()
            listening = true
            startTask()
        } catch {
            problem = "Não consegui ligar o microfone."
            stop()
        }
    }

    /// One recognition task. When it ends on its own (a long pause, or Apple's
    /// one-minute server limit) and we are still listening, the text is kept
    /// and a fresh task continues on the same microphone.
    private func startTask() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = onDevice
        request.shouldReportPartialResults = true
        if #available(iOS 16, *) { request.addsPunctuation = true }
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let text = result?.bestTranscription.formattedString {
                    self.transcript = self.joiner.update(text)
                    self.armSilenceTimer()
                }
                guard error != nil || result?.isFinal == true else { return }
                self.joiner.commit()
                self.transcript = self.joiner.text
                if self.listening {
                    self.request?.endAudio()
                    self.startTask()
                }
            }
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
        joiner.commit()
        transcript = joiner.text
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
