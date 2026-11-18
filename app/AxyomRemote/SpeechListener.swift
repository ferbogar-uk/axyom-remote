import Foundation
import AVFoundation
import Speech

/// Listens with Apple's on-device recognizer only. If this iPhone cannot
/// recognize European Portuguese on the device, it says so and does NOT fall
/// back to Apple's servers: the screen promises that recognition stays on the phone.
@MainActor
final class SpeechListener: ObservableObject {
    @Published var transcript = ""
    @Published var listening = false
    @Published var problem: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-PT"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if listening { stop() } else { start() }
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
        guard let recognizer, recognizer.isAvailable else {
            problem = "O reconhecimento de voz não está disponível agora."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            problem = "Este iPhone não reconhece português sem internet. Transfere o idioma em Definições, Geral, Teclado, Ditado."
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
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
                    if let text = result?.bestTranscription.formattedString { self.transcript = text }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
            listening = true
        } catch {
            problem = "Não consegui ligar o microfone."
            stop()
        }
    }

    func stop() {
        guard listening || engine.isRunning else { return }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
    }
}
