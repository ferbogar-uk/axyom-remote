import SwiftUI
import UIKit

/// AXYOM look, matching the desktop app: near-black and greys in dark mode,
/// white / light grey / ice in light mode (follows the iPhone setting).
/// Orange (`accent`) is kept for the two actions only: send and start voice.
/// Older token names stay as aliases so every screen picks up the new palette.
enum Theme {
    static let background = Color(light: 0xF6F7F8, dark: 0x0B0B0C)
    static let surface = Color(light: 0xFFFFFF, dark: 0x161618)
    static let elevated = Color(light: 0xECEEF1, dark: 0x1F1F22)
    static let border = Color(light: 0xDCDFE3, dark: 0x2A2A2E)
    static let borderStrong = Color(light: 0xB7BCC3, dark: 0x45454B)
    static let text = Color(light: 0x141416, dark: 0xECECEE)
    static let textSoft = Color(light: 0x2E3036, dark: 0xCFCFD4)
    static let muted = Color(light: 0x6B6F76, dark: 0x9C9CA4)
    static let green = Color(light: 0x1F9D63, dark: 0x68D6A2)
    static let danger = Color(light: 0xC8102E, dark: 0xD7263D)   // deep Ferrari-style red, less glaring on black

    /// The orange of the brand, only for send and voice.
    /// Your voice in a conversation (the app's voice is the orange accent).
    static let voiceBlue = Color(light: 0x2F7BFF, dark: 0x4C93FF)
    static let blue = voiceBlue      // "finished, unread" dot, same as the desktop
    static let accent = Color(hex: 0xFF8A1F)   // brand orange, more saturated (Ricardo, 18 Nov)
    static let onAccent = Color(hex: 0x0B0B0C)

    /// Frosted glass tints: graphite band behind the floating bars, grey for the bars.
    static let graphiteGlass = Color(light: 0xE6E9ED, dark: 0x16171A)
    static let barGlass = Color(light: 0xFFFFFF, dark: 0x55565C)   // lighter grey glass, like the Claude composer

    // Aliases from the first (amber-heavy) design, now neutral.
    static let amber = text
    /// Kanban phase tags, yellow like on the PC.
    static let phase = Color(light: 0xA86B12, dark: 0xF2C14E)
    /// Dot colour per kanban phase (text stays grey).
    static func phaseDot(_ label: String) -> Color {
        switch label {
        case "Planeamento": return Color(light: 0x2F7BFF, dark: 0x6AA6FF)
        case "A implementar": return phase
        case "A validar": return Color(light: 0x8A4FD6, dark: 0xB58CFF)
        case "Concluído": return green
        default: return Color(light: 0x8A8F98, dark: 0x8A8F98)
        }
    }
    static let amberLight = text
    static let amberSurface = surface
    static let amberFill = elevated
    static let amberBorder = border
    static let onAmber = background
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// A colour that follows light / dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Theme.onAmber : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Theme.amber : Theme.border, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(isEnabled ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension View {
    func card(fill: Color = Theme.surface, stroke: Color = Theme.border) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(stroke, lineWidth: 1))
    }

    func sectionLabel(_ color: Color = Theme.muted) -> some View {
        // Sentence case, no spaced capitals (design review 20 Nov 2026).
        font(.subheadline.weight(.semibold)).foregroundStyle(color == Theme.muted ? Theme.textSoft : color)
    }
}
