import SwiftUI
import UIKit
import AxyomRemoteCore

/// Widget content, shared by the widget extension and the app's demo screen
/// (so CI screenshots show exactly what the widget draws). Plain SwiftUI only.
enum WidgetLook: String, CaseIterable { case summary, sessions, usage }
enum WidgetSize { case small, medium, large, lockRect, lockCircle, lockInline }

enum WidgetPalette {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(widgetHex: dark) : UIColor(widgetHex: light) })
    }
    // Same values as the app's Theme.
    static let text = dyn(0x141414, 0xF2F2F2)
    static let muted = dyn(0x6B6B70, 0x9A9AA0)
    static let track = dyn(0xE4E4E8, 0x2C2C30)
    static let yellow = dyn(0xA86B12, 0xF2C14E)
    static let green = dyn(0x1F9D63, 0x68D6A2)
    static let blue = dyn(0x2F7BFF, 0x4C93FF)
    static let red = dyn(0xC8102E, 0xD7263D)
    static let accent = Color(red: 1, green: 0.55, blue: 0.13)

    static func dot(_ d: FleetSession.Dot?) -> Color? {
        switch d {
        case .needsYou?: return yellow
        case .working?: return green
        case .done?: return blue
        case nil: return nil
        }
    }
    static func ring(_ status: Int) -> Color { status >= 2 ? red : status == 1 ? yellow : green }
}

private extension UIColor {
    convenience init(widgetHex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct AxyomWidgetView: View {
    let snap: WidgetSnapshot
    let look: WidgetLook
    let size: WidgetSize
    var now = Date()

    var body: some View {
        switch size {
        case .lockInline: Text(inlineText)
        case .lockCircle: lockCircle
        case .lockRect: lockRect
        default:
            if snap.updatedAt == .distantPast {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    Spacer()
                    Text("Abre a app para ligar ao PC.").font(.footnote).foregroundStyle(WidgetPalette.muted)
                }
            } else {
                switch look {
                case .summary: summary
                case .sessions: sessions
                case .usage: usage
                }
            }
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(spacing: 6) {
            Text("AXYOM").font(.caption.weight(.heavy)).foregroundStyle(WidgetPalette.text)
            Spacer(minLength: 4)
            Circle().fill(snap.pcOnline ? WidgetPalette.green : WidgetPalette.muted).frame(width: 7, height: 7)
            if size != .small {
                Text(snap.pcOnline ? (snap.pcName ?? "PC") : "PC offline").font(.caption2).foregroundStyle(WidgetPalette.muted).lineLimit(1)
            }
        }
    }

    private var updated: some View {
        Text(snap.updatedAt, style: .relative).font(.caption2).foregroundStyle(WidgetPalette.muted).lineLimit(1)
    }

    private func count(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text("\(n)").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(WidgetPalette.text)
            Text(label).font(.caption).foregroundStyle(WidgetPalette.muted).lineLimit(1)
        }
    }

    private func row(_ i: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 7) {
            Circle().fill(WidgetPalette.dot(i.dot) ?? WidgetPalette.track).frame(width: 8, height: 8)
            Text(i.title).font(.caption).foregroundStyle(WidgetPalette.text).lineLimit(1)
        }
    }

    private func ring(_ r: WidgetSnapshot.Ring, side: CGFloat, line: CGFloat) -> some View {
        ZStack {
            Circle().stroke(WidgetPalette.track, lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(min(100, max(2, r.percent))) / 100)
                .stroke(WidgetPalette.ring(r.status), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: side, height: side)
    }

    private func ringChip(_ r: WidgetSnapshot.Ring) -> some View {
        HStack(spacing: 5) {
            ring(r, side: 16, line: 2.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.label).font(.system(size: 10)).foregroundStyle(WidgetPalette.muted).lineLimit(1)
                Text("\(r.percent)%").font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(WidgetPalette.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstWaiting: WidgetSnapshot.Item? { snap.items.first { $0.dot == .needsYou } }

    // MARK: looks

    private var summary: some View {
        VStack(alignment: .leading, spacing: size == .small ? 6 : 8) {
            header
            if size == .small {
                Spacer(minLength: 0)
                count(snap.waitingCount, "à espera", WidgetPalette.yellow)
                count(snap.workingCount, "a trabalhar", WidgetPalette.green)
                Spacer(minLength: 0)
                updated
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        count(snap.waitingCount, "à tua espera", WidgetPalette.yellow)
                        if let w = firstWaiting {
                            Text(w.title).font(.caption).foregroundStyle(WidgetPalette.text).lineLimit(1).padding(.leading, 15)
                        }
                        count(snap.workingCount, "a trabalhar", WidgetPalette.green)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                if !snap.rings.isEmpty {
                    HStack(spacing: 6) { ForEach(Array(snap.rings.prefix(4).enumerated()), id: \.offset) { ringChip($0.element) } }
                }
                if size == .large {
                    Divider().padding(.vertical, 2)
                    ForEach(Array(snap.items.prefix(6).enumerated()), id: \.offset) { row($0.element) }
                    Spacer(minLength: 0)
                    updated
                }
            }
        }
    }

    private var sessions: some View {
        let n = size == .small ? 3 : size == .medium ? 4 : 8
        return VStack(alignment: .leading, spacing: size == .small ? 7 : 8) {
            header
            if snap.items.isEmpty {
                Spacer()
                Text("Sem sessões").font(.footnote).foregroundStyle(WidgetPalette.muted)
                Spacer()
            } else {
                ForEach(Array(snap.items.prefix(n).enumerated()), id: \.offset) { row($0.element) }
                Spacer(minLength: 0)
            }
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Uso dos planos").font(.caption.weight(.heavy)).foregroundStyle(WidgetPalette.text)
            if snap.rings.isEmpty {
                Spacer()
                Text("Sem dados de uso").font(.footnote).foregroundStyle(WidgetPalette.muted)
                Spacer()
            } else {
                ForEach(Array(snap.rings.prefix(size == .small ? 3 : 4).enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 8) {
                        ring(r, side: size == .small ? 18 : 22, line: 3)
                        Text(r.label).font(.caption).foregroundStyle(WidgetPalette.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(r.percent)%").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(WidgetPalette.ring(r.status))
                        if size != .small, let t = WidgetSnapshot.resetText(r.resetsAt, now: now) {
                            Text(t).font(.caption2).foregroundStyle(WidgetPalette.muted).lineLimit(1).fixedSize()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: lock screen

    private var inlineText: String {
        if snap.waitingCount > 0 { return "AXYOM · \(snap.waitingCount) à espera" }
        if snap.workingCount > 0 { return "AXYOM · \(snap.workingCount) a trabalhar" }
        return snap.pcOnline ? "AXYOM · tudo em dia" : "AXYOM · PC offline"
    }

    private var lockCircle: some View {
        ZStack {
            Circle().stroke(lineWidth: 3).opacity(0.3)
            VStack(spacing: 0) {
                Text("\(snap.waitingCount)").font(.title2.weight(.bold).monospacedDigit())
                Text("espera").font(.system(size: 9))
            }
        }
    }

    private var lockRect: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("AXYOM").font(.caption.weight(.heavy))
                Label("\(snap.waitingCount)", systemImage: "hand.raised.fill").font(.caption.monospacedDigit())
                Label("\(snap.workingCount)", systemImage: "bolt.fill").font(.caption.monospacedDigit())
            }
            Text(firstWaiting?.title ?? (snap.pcOnline ? "Nada à tua espera" : "PC offline")).font(.caption).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
