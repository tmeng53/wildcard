#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// An emoji flying on an arc from where it was picked to the author's head, where it pops. The
/// double tap's heart first pops big where the finger was, holds, then shrinks as it flies.
struct FlyingEmoji: View {
    let flight: FeedModel.Flight
    let target: CGPoint
    @State private var progress = 0.0
    @State private var scale: Double
    @State private var opacity = 1.0

    private static let size: Double = 28
    private static let bigSize: Double = 96
    private static let arcLift: Double = 80

    init(flight: FeedModel.Flight, to target: CGPoint) {
        self.flight = flight
        self.target = target
        _scale = State(initialValue: flight.big ? 0 : 1)
    }

    var body: some View {
        Text(verbatim: flight.emoji.text)
            .font(.system(size: flight.big ? Self.bigSize : Self.size))
            .scaleEffect(scale)
            .opacity(opacity)
            .modifier(Arc(from: flight.from, target: target, lift: Self.arcLift, progress: progress))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                let landed = flight.big ? Self.size / Self.bigSize : 1
                if flight.big {
                    withAnimation(.wildcard(Motion.celebrate)) { scale = 1 }
                    try? await Task.sleep(for: .seconds(FeedModel.bigHold))
                }
                withAnimation(.easeInOut(duration: FeedModel.flight)) {
                    progress = 1
                    scale = landed
                }
                try? await Task.sleep(for: .seconds(FeedModel.flight))
                withAnimation(.easeOut(duration: 0.15)) {
                    scale = landed * 1.4
                    opacity = 0
                }
            }
    }
}

/// Places a view along a curve from `from` to `target` that rises `lift` above the higher end.
private struct Arc: ViewModifier, Animatable {
    let from: CGPoint
    let target: CGPoint
    let lift: Double
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let control = CGPoint(x: (from.x + target.x) / 2, y: min(from.y, target.y) - lift)
        let fraction = progress
        let rest = 1 - fraction
        let point = CGPoint(
            x: rest * rest * from.x + 2 * rest * fraction * control.x + fraction * fraction * target.x,
            y: rest * rest * from.y + 2 * rest * fraction * control.y + fraction * fraction * target.y)
        return content.position(point)
    }
}
#endif
