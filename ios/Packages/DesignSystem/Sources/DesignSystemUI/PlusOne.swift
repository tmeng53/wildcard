#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The big 「+1」 that pops out over a character's head when they check in: it springs up, rises
/// and fades. It plays each time `trigger` changes; with Reduce Motion on it only fades in and
/// out. Put it in an overlay above the head; it takes no taps.
public struct PlusOne<Trigger: Equatable>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let trigger: Trigger

    public init(trigger: Trigger) {
        self.trigger = trigger
    }

    private struct Frame {
        var scale = 0.4
        var rise = 0.0
        var opacity = 0.0
    }

    public var body: some View {
        Text(verbatim: "+1")
            .typeStyle(TypeRamp.scoreHero)
            .foregroundStyle(Color(role: .ring, in: theme))
            .keyframeAnimator(initialValue: Frame(), trigger: trigger) { content, frame in
                content
                    .scaleEffect(reduceMotion ? 1 : frame.scale, anchor: .bottom)
                    .offset(y: reduceMotion ? 0 : -frame.rise)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                let show = Motion.plusOneDuration
                KeyframeTrack(\.scale) {
                    SpringKeyframe(
                        1, duration: Motion.celebrate.response,
                        spring: Spring(
                            response: Motion.celebrate.response, dampingRatio: Motion.celebrate.dampingFraction))
                    CubicKeyframe(1, duration: show - Motion.celebrate.response)
                }
                KeyframeTrack(\.rise) {
                    CubicKeyframe(Motion.plusOneRise, duration: show)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: Motion.reducedDuration)
                    LinearKeyframe(1, duration: show - 2 * Motion.reducedDuration)
                    LinearKeyframe(0, duration: Motion.reducedDuration)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
