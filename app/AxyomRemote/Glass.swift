import SwiftUI

/// Dark surround for the floating bar: from the bar's top down to the bottom
/// edge of the screen, full width, its top edge following the bar's rounded
/// outline, and reaching a few millimetres inside the bar so the glass has a
/// dark rim. The middle of the bar stays see-through. Only a faint shadow of
/// what scrolls past shows through. Solid with Reduce Transparency.
struct FrostedBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduce
    /// The bar's corner radius; nil = capsule.
    var cornerRadius: CGFloat? = nil
    /// Space between the bar and the screen sides / bottom of its container.
    var inset = EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12)

    var body: some View {
        BarSurround(cornerRadius: cornerRadius, inset: inset)
            .fill(reduce ? Theme.background : Theme.background.opacity(0.93), style: FillStyle(eoFill: true))
            // Drawn as the bar's own background, grown out to the screen sides and down.
            .padding(EdgeInsets(top: -inset.top, leading: -inset.leading, bottom: -inset.bottom, trailing: -inset.trailing))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Outer shape (bar outline widened to the screen sides, then straight down
/// past the bottom edge) with a hole slightly smaller than the bar.
struct BarSurround: Shape {
    var cornerRadius: CGFloat?
    var inset: EdgeInsets
    /// How far the dark reaches inside the bar (a few millimetres).
    var inside: CGFloat = 9
    /// Below the container, through the home-indicator area to the screen edge.
    var below: CGFloat = 60

    func path(in rect: CGRect) -> Path {
        let bar = CGRect(x: rect.minX + inset.leading, y: rect.minY + inset.top,
                         width: rect.width - inset.leading - inset.trailing,
                         height: rect.height - inset.top - inset.bottom)
        let r = min(cornerRadius ?? bar.height / 2, bar.height / 2)
        var p = Path()
        // Outer: rounded top following the bar, out to the screen sides.
        let outer = CGRect(x: rect.minX, y: bar.minY, width: rect.width, height: rect.maxY + below - bar.minY)
        p.addRoundedRect(in: outer, cornerSize: CGSize(width: r, height: r), style: .continuous)
        // Hole: the bar, a few millimetres smaller.
        let hole = bar.insetBy(dx: inside, dy: inside)
        let hr = max(0, r - inside)
        p.addRoundedRect(in: hole, cornerSize: CGSize(width: hr, height: hr), style: .continuous)
        return p
    }
}

extension View {
    /// The floating bar itself: one see-through frosted glass like Claude's
    /// composer (content blurred behind it), a light rim on top.
    func glassBar<S: InsettableShape>(_ shape: S) -> some View {
        modifier(GlassBar(shape: shape))
    }
}

private struct GlassBar<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduce

    func body(content: Content) -> some View {
        content
            .background {
                if reduce {
                    shape.fill(Theme.surface)
                } else {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Theme.barGlass.opacity(0.28))
                    }
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
