import Foundation
import AVFoundation
import AxyomRemoteCore

/// Reads the agent's replies aloud. With the Azure voice on (Settings) and the
/// server configured, it plays the neural voice the server returns; on any
/// failure it carries on with the iPhone's own voice for the rest of the reply.
///
/// `speaking` turns false only when the whole reply has finished or was
/// stopped: the conversation loop waits on it to open the microphone again.
@MainActor
final class ReplySpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    /// Fetches MP3 for one piece of text, or nil. Set by AppModel when the server has a voice.
    static var neural: ((String) async -> Data?)?

    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()
    private var pending = 0
    private var player: AVAudioPlayer?
    private var playerDone: CheckedContinuation<Void, Never>?
    private var job: Task<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    private static var voice: AVSpeechSynthesisVoice? {
        let first = Prefs.voiceLanguage, second = first == "pt-PT" ? "pt-BR" : "pt-PT"
        return AVSpeechSynthesisVoice(language: first) ?? AVSpeechSynthesisVoice(language: second)
    }

    func speak(_ lines: [String]) {
        let clean = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try? audio.setActive(true)
        speaking = true
        if Prefs.voiceEngine == "azure", let neural = Self.neural {
            let pieces = NeuralVoice.chunks(clean.joined(separator: "\n"))
            job = Task { [weak self] in await self?.playNeural(pieces, fetch: neural) }
        } else {
            speakSystem(clean)
        }
    }

    /// Fetch the next piece while the current one plays, so there is no gap.
    private func playNeural(_ pieces: [String], fetch: @escaping (String) async -> Data?) async {
        var next: Task<Data?, Never>? = pieces.isEmpty ? nil : Task { await fetch(pieces[0]) }
        for i in pieces.indices {
            guard !Task.isCancelled, let current = next else { return }
            let data = await current.value
            next = i + 1 < pieces.count ? Task { await fetch(pieces[i + 1]) } : nil
            guard !Task.isCancelled else { next?.cancel(); return }
            guard let data, let p = try? AVAudioPlayer(data: data) else {
                next?.cancel()
                job = nil
                speakSystem(Array(pieces[i...]))     // fall back for what is left
                return
            }
            p.delegate = self
            player = p
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                playerDone = c
                if !p.play() { playerDone = nil; c.resume() }
            }
            player = nil
        }
        guard !Task.isCancelled else { return }
        job = nil
        if pending == 0 { speaking = false }
    }

    private func speakSystem(_ lines: [String]) {
        for line in lines {
            let utterance = AVSpeechUtterance(string: line)
            utterance.voice = Self.voice
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Prefs.speechRateMultiplier)
            pending += 1
            synth.speak(utterance)
        }
        speaking = true
    }

    func stop() {
        job?.cancel()
        job = nil
        player?.stop()
        player = nil
        resumePlayer()
        pending = 0
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    private func resumePlayer() {
        let c = playerDone
        playerDone = nil
        c?.resume()
    }

    private func finishedOne() {
        pending = max(0, pending - 1)
        if pending == 0 && job == nil { speaking = false }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resumePlayer() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.resumePlayer() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }
}
