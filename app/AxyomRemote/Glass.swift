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
                Theme.background.opacity(0.86)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28), .init(color: .black, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

extension View {
    /// The floating bar itself: grey frosted glass, mostly opaque.
    func glassBar<S: Shape>(_ shape: S) -> some View {
        modifier(GlassBar(shape: shape))
    }
}

private struct GlassBar<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduce

    func body(content: Content) -> some View {
        content
            .background {
                if reduce {
                    shape.fill(Theme.surface)
                } else {
                    ZStack {
                        shape.fill(.regularMaterial)
                        shape.fill(Theme.barGlass.opacity(0.72))
                    }
                }
            }
            .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }
}
