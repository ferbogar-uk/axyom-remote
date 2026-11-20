import SwiftUI
import UIKit

/// AXYOM look, matching the desktop app: near-black and greys in dark mode,
/// white / light grey / ice in light mode (follows the iPhone setting).
/// Orange (`accent`) is kept for the two actions only: send and start voice.
/// Older token names stay as aliases so every screen picks up the new palette.
enum Theme {
    // "Aço e brasa" (Ricardo, 20 Nov 2026): the logo's blued steel for the ground and
    // cards, its amber glow only for what is live or waiting for you.
    // Dark: graphite-navy. Light: steel paper with navy ink.
    static let background = Color(light: 0xEEF1F5, dark: 0x0B0F14)
    static let surface = Color(light: 0xFFFFFF, dark: 0x111A26)
    static let elevated = Color(light: 0xE3E8EF, dark: 0x17283D)
    static let border = Color(light: 0xD3DAE3, dark: 0x1D2B3D)
    static let borderStrong = Color(light: 0xAEB9C7, dark: 0x2E4560)
    static let text = Color(light: 0x0F1B2D, dark: 0xE5E7EB)
    static let textSoft = Color(light: 0x24344A, dark: 0xC9D1DB)
    static let muted = Color(light: 0x56667B, dark: 0x9AA8BA)
    static let green = Color(light: 0x1F9D63, dark: 0x5FD49C)
    static let danger = Color(light: 0xC8102E, dark: 0xE0444F)

    /// Steel bevel on cards: a lighter top edge fading into the border, like the logo's facets.
    static let bevelTop = Color(light: 0xE4E9F0, dark: 0x2D425C)
    static let bevelBottom = Color(light: 0xC8D1DC, dark: 0x16222F)
    static let shadow = Color(light: 0x0F1B2D, dark: 0x000000)
    static let shadowOpacity: Double = 0.07

    /// Your voice in a conversation (the app's voice is the amber accent).
    static let voiceBlue = Color(light: 0x2F6FE0, dark: 0x5B9BFF)
    static let blue = voiceBlue      // "finished, unread" dot, same as the desktop
    /// The logo's amber glow: send, voice, Permitir, and the waiting hairline.
    static let accent = Color(light: 0xF08A12, dark: 0xFF9F3D)
    static let onAccent = Color(hex: 0x10141B)
    /// Ember tint for the one authored glow behind the logo on the home screen.
    static let ember = Color(hex: 0xFF9F3D)

    /// Frosted glass tints: steel band behind the floating bars, blued grey for the bars.
    static let graphiteGlass = Color(light: 0xE3E8EF, dark: 0x0E1520)
    static let barGlass = Color(light: 0xFFFFFF, dark: 0x34465E)

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
    /// Amber hairline round anything waiting for you.
    static let amberBorder = Color(light: 0xF0A24C, dark: 0xA0631F)
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
            .steelSurface(fill: fill, stroke: stroke, radius: 18)
    }

    /// Blued-steel panel: fill, a bevelled edge (lighter on top, like the logo's facets)
    /// and a soft, offset shadow. A custom stroke (amber for waiting) replaces the bevel.
    func steelSurface(fill: Color = Theme.surface, stroke: Color = Theme.border, radius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let bevel = stroke == Theme.border
        return background(fill, in: shape)
            .overlay {
                if bevel {
                    shape.strokeBorder(LinearGradient(colors: [Theme.bevelTop, Theme.bevelBottom], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                } else {
                    shape.strokeBorder(stroke, lineWidth: 1)
                }
            }
            .shadow(color: Theme.shadow.opacity(Theme.shadowOpacity), radius: 10, x: 0, y: 4)
    }

    func sectionLabel(_ color: Color = Theme.muted) -> some View {
        // Sentence case, no spaced capitals (design review 20 Nov 2026).
        font(.subheadline.weight(.semibold)).foregroundStyle(color == Theme.muted ? Theme.textSoft : color)
    }
}

/// The AXYOM lockup: the dimensional symbol plus the brand wordmark, drawn as a
/// template so it reads navy on light and steel-white on dark.
struct BrandMark: View {
    var symbol: CGFloat = 38
    var body: some View {
        HStack(spacing: symbol * 0.26) {
            Image("AxyomSymbol").resizable().scaledToFit().frame(height: symbol)
            Image("AxyomWordmark").renderingMode(.template).resizable().scaledToFit()
                .frame(height: symbol * 0.42).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AXYOM")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The home screen's one authored moment: a faint ember glow behind the logo, as if
/// the symbol's amber edge lit the steel. Static, sits under everything, no motion.
struct BrandBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background
            RadialGradient(colors: [Theme.ember.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           center: UnitPoint(x: 0.12, y: 0.02), startRadius: 0, endRadius: 320)
            if scheme == .dark {
                LinearGradient(colors: [Color(hex: 0x0F1B2D).opacity(0.9), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
