import SwiftUI
import UIKit

/// User settings, stored on the iPhone (UserDefaults). Read by views through
/// @AppStorage and by non-view classes (speech, notifications) through `Prefs`.
enum Prefs {
    enum Key {
        static let appearance = "appearance"          // system | light | dark
        static let voiceLanguage = "voiceLanguage"    // pt-BR | pt-PT
        static let speechRate = "speechRate"          // slow | normal | fast
        static let silence = "silenceSeconds"         // 1.5 | 2.0 | 2.5
        static let voiceEngine = "voiceEngine"        // azure | system
        static let azureVoice = "azureVoice"          // "" = server default (the desktop's voice)
        static let haptics = "haptics"
        static let notifications = "notifications"
        static let notifyFinished = "notifyFinished"
        static let notifyLimit = "notifyLimit"
        static let faceID = "faceID"
        static let quickReplies = "quickReplies"
    }

    private static var d: UserDefaults { .standard }

    static var voiceLanguage: String { d.string(forKey: Key.voiceLanguage) ?? "pt-BR" }
    static var silenceSeconds: TimeInterval {
        let v = d.double(forKey: Key.silence)
        return v > 0 ? v : 1.8
    }
    static var speechRateMultiplier: Float {
        switch d.string(forKey: Key.speechRate) ?? "normal" {
        case "slow": return 0.92
        case "fast": return 1.25
        default: return 1.08
        }
    }
    static var voiceEngine: String { d.string(forKey: Key.voiceEngine) ?? "azure" }
    static var azureVoice: String { d.string(forKey: Key.azureVoice) ?? "" }
    static var haptics: Bool { d.object(forKey: Key.haptics) as? Bool ?? true }
    static var notifications: Bool { d.object(forKey: Key.notifications) as? Bool ?? true }
    static var notifyFinished: Bool { d.object(forKey: Key.notifyFinished) as? Bool ?? true }
    static var notifyLimit: Bool { d.object(forKey: Key.notifyLimit) as? Bool ?? true }
    static var faceID: Bool { d.object(forKey: Key.faceID) as? Bool ?? true }
    /// One phrase per line.
    static let defaultQuickReplies = "Continua\nCorre os testes\nFaz commit\nResume o que fizeste"
    static var quickReplies: [String] {
        (d.string(forKey: Key.quickReplies) ?? defaultQuickReplies)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func colorScheme(_ raw: String) -> ColorScheme? {
        switch raw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// A light tap when something is sent or answered (if enabled).
    @MainActor static func tap() {
        guard haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
