import SwiftUI

/// Strip below the floating bar to the bottom edge of the screen (not behind
/// the bar), full width, in
/// the screen's own background colour (no grey band): what scrolls underneath
/// is blurred and dimmed, so you can tell something is there but not read it.
/// Fades in at the top so there is no hard line. Solid when the user turns on
/// Reduce Transparency.
struct FrostedBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduce
    /// Height above the bottom of the bar's container (its lower padding plus a little of the bar).
    var height: CGFloat = 14
    /// How far it reaches below the container, through the home-indicator area to the screen edge.
    private let below: CGFloat = 60

    var body: some View {
        (reduce ? Theme.background : Theme.background.opacity(0.92))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: min(1, 10 / (height + below))),
                                         .init(color: .black, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: height + below)
            .offset(y: below)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
                        shape.fill(Theme.barGlass.opacity(0.2))
                    }
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
