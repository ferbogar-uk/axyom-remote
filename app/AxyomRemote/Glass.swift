import SwiftUI

/// Dark surround for the floating bar, behind it: from the bottom edge of the
/// screen up the sides to the middle of the bar (where its edge is still
/// straight), following the bar's edge exactly and 1 mm inside it so no line
/// of background shows. It fades out towards the top, and only shows while
/// something is actually scrolling under the bar. Solid with Reduce Transparency.
struct FrostedBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduce
    /// The bar's corner radius; nil = capsule.
    var cornerRadius: CGFloat? = nil
    /// Something is scrolling underneath (see `contentBehindBar`).
    var active: Bool = true
    /// Space between the bar and the screen sides / bottom of its container.
    var inset = EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12)

    var body: some View {
        GeometryReader { g in
            let bar = CGRect(x: inset.leading, y: inset.top,
                             width: g.size.width - inset.leading - inset.trailing,
                             height: g.size.height - inset.top - inset.bottom - BarSurround.below)
            let total = g.size.height
            // Clear at the middle of the bar, full by its lower quarter.
            let start = bar.midY / total, full = (bar.midY + bar.height / 4) / total
            BarSurround(cornerRadius: cornerRadius, bar: bar)
                .fill(reduce ? Theme.background : Theme.background.opacity(0.93))
                .mask(LinearGradient(stops: [.init(color: .clear, location: start), .init(color: .black, location: full),
                                             .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
        }
        // Drawn as the bar's own background, grown out to the screen sides and down.
        .padding(EdgeInsets(top: -inset.top, leading: -inset.leading, bottom: -inset.bottom - BarSurround.below, trailing: -inset.trailing))
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// From the bar's middle down past the screen bottom, full width, minus the
/// bar shrunk by 1 mm.
struct BarSurround: Shape {
    var cornerRadius: CGFloat?
    var bar: CGRect
    /// 1 mm inside the bar, behind the glass, so no hairline of background shows.
    var inside: CGFloat = 3
    static let below: CGFloat = 60

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius ?? bar.height / 2, bar.height / 2)
        let outer = Path(CGRect(x: rect.minX, y: bar.midY, width: rect.width, height: rect.maxY - bar.midY))
        let hole = bar.insetBy(dx: inside, dy: inside)
        let hr = max(0, r - inside)
        return outer.subtracting(Path(roundedRect: hole, cornerSize: CGSize(width: hr, height: hr), style: .continuous))
    }
}

extension View {
    /// Reports whether scroll content currently runs underneath the bottom bar.
    func contentBehindBar(_ value: Binding<Bool>) -> some View { modifier(ContentBehindBar(value: value)) }
}

private struct ContentBehindBar: ViewModifier {
    @Binding var value: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { g in
                g.contentSize.height - g.contentOffset.y > g.containerSize.height - g.contentInsets.bottom + 1
            } action: { _, behind in value = behind }
        } else {
            content
        }
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
                        shape.fill(.ultraThinMaterial).opacity(0.75)
                        shape.fill(Theme.barGlass.opacity(0.14))
                    }
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            // Thin line of light along the top edge, like Claude's composer.
            .overlay(shape.strokeBorder(LinearGradient(stops: [.init(color: Color.white.opacity(0.5), location: 0),
                                                               .init(color: .clear, location: 0.18)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
