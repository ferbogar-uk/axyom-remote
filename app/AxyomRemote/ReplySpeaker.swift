import Foundation
import AVFoundation

/// Reads the agent's replies aloud with the iPhone's own voice (no server,
/// no cost). Brazilian Portuguese first, then European, else the system default.
///
/// `speaking` turns false only when the last queued sentence has finished or was
/// cancelled: the conversation loop waits on it to open the microphone again.
/// (Reading `isSpeaking` inside the finish callback is not reliable; it can
/// still be true for the last utterance, which left the loop stuck.)
@MainActor
final class ReplySpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()
    private var pending = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    private static let voice: AVSpeechSynthesisVoice? =
        AVSpeechSynthesisVoice(language: "pt-BR") ?? AVSpeechSynthesisVoice(language: "pt-PT")

    func speak(_ lines: [String]) {
        let clean = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try? audio.setActive(true)
        for line in clean {
            let utterance = AVSpeechUtterance(string: line)
            utterance.voice = Self.voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
            pending += 1
            synth.speak(utterance)
        }
        speaking = true
    }

    func stop() {
        pending = 0
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    private func finishedOne() {
        pending = max(0, pending - 1)
        if pending == 0 { speaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }
}
