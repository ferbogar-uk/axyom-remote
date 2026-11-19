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
///
/// With the Azure voice on and the server able to transcribe, the same
/// microphone audio is also kept (16 kHz mono) and sent to the server when you
/// stop; its text replaces Apple's. Apple's live text stays as the fallback.
@MainActor
final class SpeechListener: ObservableObject {
    /// Sends a WAV and a language ("pt-BR") to the server, returns the text or nil. Set by AppModel.
    static var azureSTT: ((Data, String) async -> String?)?

    @Published var transcript = ""
    @Published var listening = false
    /// Microphone off, waiting for the server's transcription (listening is still true).
    @Published var transcribing = false
    /// Microphone loudness 0…1 (smoothed), for the blue glow.
    @Published var level: CGFloat = 0
    @Published var problem: String?
    /// Whether the last recognition ran on the iPhone (false = Apple's servers).
    @Published var onDevice = true

    private var recognizer: SFSpeechRecognizer?
    private var joiner = TranscriptJoiner()

    /// Portuguese recognizer: on-device if any variant supports it, else the first available one.
    private static func pickRecognizer() -> SFSpeechRecognizer? {
        let ids = Prefs.voiceLanguage == "pt-PT" ? ["pt-PT", "pt-BR"] : ["pt-BR", "pt-PT"]
        let all = ids.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
        return all.first { $0.isAvailable && $0.supportsOnDeviceRecognition } ?? all.first { $0.isAvailable } ?? all.first
    }
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var autoStop = false
    private var collector: PCMCollector?
    private var sttTask: Task<Void, Never>?
    /// Bumped on every new recognition task and on stop: a late result from an
    /// old task (iOS sends one more "final" after we stop) is ignored. It used
    /// to be added again, so what you said appeared twice.
    private var generation = 0
    /// Seconds of silence after speech that end listening when auto-stop is on.
    /// 1.8 s: pauses no longer erase what was said (TranscriptJoiner keeps it),
    /// so the wait can be shorter than AVA's 2.5 s; tapping still sends at once.
    var silenceSeconds: TimeInterval { Prefs.silenceSeconds }

    func toggle(autoStop: Bool = false) {
        if transcribing { return }
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
            let format = input.outputFormat(forBus: 0)
            let keep = Prefs.voiceEngine == "azure" && Self.azureSTT != nil ? PCMCollector(from: format) : nil
            collector = keep
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                keep?.append(buffer)
                let loud = Self.loudness(buffer)
                // The current request changes when a task is restarted after a pause.
                Task { @MainActor in
                    self?.request?.append(buffer)
                    if let self { self.level = self.level * 0.6 + loud * 0.4 }
                }
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
        generation += 1
        let mine = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == mine, self.listening, !self.transcribing else { return }
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

    /// RMS of the first channel mapped to 0…1 (about -50 dB … -10 dB).
    nonisolated static func loudness(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        return CGFloat(min(1, max(0, (db + 50) / 40)))
    }

    /// Stop listening. `discard` (leaving the conversation) skips the server transcription.
    func stop(discard: Bool = false) {
        level = 0
        silenceTimer?.invalidate()
        silenceTimer = nil
        if discard, transcribing {
            sttTask?.cancel(); sttTask = nil
            transcribing = false
            listening = false
            return
        }
        guard !transcribing, listening || engine.isRunning else { return }
        generation += 1          // ignore anything the old task still sends
        joiner.commit()
        transcript = joiner.text
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        let samples = collector?.take() ?? []
        collector = nil
        // Under a quarter of a second is nothing worth sending.
        guard !discard, let stt = Self.azureSTT, samples.count > NeuralVoice.sttSampleRate / 4 else {
            listening = false
            return
        }
        transcribing = true
        let language = Prefs.voiceLanguage
        sttTask = Task { [weak self] in
            let text = await stt(NeuralVoice.wav(samples: samples), language)
            guard let self, !Task.isCancelled else { return }
            if let text, !text.isEmpty { self.transcript = text }
            self.transcribing = false
            self.listening = false
            self.sttTask = nil
        }
    }
}

/// Keeps the microphone audio as 16 kHz mono 16-bit samples (up to 60 s) for
/// the server transcription. Called on the audio thread.
final class PCMCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16] = []
    private let converter: AVAudioConverter?
    private let out: AVAudioFormat?
    private let limit = NeuralVoice.sttSampleRate * NeuralVoice.maxSttSeconds

    init(from input: AVAudioFormat) {
        out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(NeuralVoice.sttSampleRate), channels: 1, interleaved: true)
        converter = out.flatMap { AVAudioConverter(from: input, to: $0) }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let out, buffer.frameLength > 0 else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * out.sampleRate / buffer.format.sampleRate) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = converted.int16ChannelData else { return }
        let n = Int(converted.frameLength)
        lock.lock(); defer { lock.unlock() }
        guard samples.count < limit else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: min(n, limit - samples.count)))
    }

    func take() -> [Int16] {
        lock.lock(); defer { lock.unlock() }
        let s = samples
        samples = []
        return s
    }
}
