import Foundation
import AVFoundation

/// Reads the agent's replies aloud with the iPhone's own voice (no server,
/// no cost). European Portuguese when the phone has it, otherwise the system default.
@MainActor
final class ReplySpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try? audio.setActive(true)
        let voice = AVSpeechSynthesisVoice(language: "pt-PT") ?? AVSpeechSynthesisVoice(language: "pt-BR")
        for line in lines {
            let utterance = AVSpeechUtterance(string: line)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        }
        speaking = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = self.synth.isSpeaking }
    }
}
