import SwiftUI

/// The approved AXYOM Remote look (docs/DESIGN.md): dark ground, amber for
/// actions, green for "ok". Colours are fixed on purpose: the approved
/// mockups are dark only, so there is no light variant to adapt to.
enum Theme {
    static let background = Color(hex: 0x0E0F12)
    static let surface = Color(hex: 0x16181D)
    static let border = Color(hex: 0x262930)
    static let borderStrong = Color(hex: 0x3A3D45)
    static let text = Color(hex: 0xECEDEF)
    static let textSoft = Color(hex: 0xD4D6DA)
    static let muted = Color(hex: 0xA3A7AE)
    static let amber = Color(hex: 0xF5A524)
    static let amberLight = Color(hex: 0xFFC35C)
    static let amberSurface = Color(hex: 0x1A1508)
    static let amberFill = Color(hex: 0x2A1E08)
    static let amberBorder = Color(hex: 0x5C4410)
    static let onAmber = Color(hex: 0x1A1206)
    static let green = Color(hex: 0x3DD68C)
    static let danger = Color(hex: 0xFF8A80)
}

extension Color {
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
        font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.6).foregroundStyle(color)
    }
}
