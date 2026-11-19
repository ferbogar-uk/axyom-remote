import SwiftUI

/// See-through band from the floating bar to the bottom edge, full width, in
/// the screen's own background colour (no grey band): what scrolls underneath
/// is blurred and dimmed, so you can tell something is there but not read it.
/// Fades in at the top so there is no hard line. Solid when the user turns on
/// Reduce Transparency.
struct FrostedBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduce

    var body: some View {
        ZStack {
            if reduce {
                Theme.background
            } else {
                // No system material: it always lifts the colour towards grey.
                // Plain background colour, slightly see-through.
                Theme.background.opacity(0.72)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28), .init(color: .black, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
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
                        shape.fill(Theme.barGlass.opacity(0.38))
                    }
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
