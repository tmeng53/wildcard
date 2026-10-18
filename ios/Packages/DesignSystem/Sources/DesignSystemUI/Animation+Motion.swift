#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

extension Animation {
    /// The animation for a motion token. With Reduce Motion on, it becomes a short ease-out
    /// with no overshoot.
    public static func wildcard(_ spring: MotionSpring, reduceMotion: Bool = false) -> Animation {
        if reduceMotion {
            return .easeOut(duration: Motion.reducedDuration)
        }
        return .spring(response: spring.response, dampingFraction: spring.dampingFraction)
    }
}

/// Shrinks a control while it is held (`snappy`) and springs it back with `panel`.
public struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.pressedScale : 1)
            .animation(
                .wildcard(configuration.isPressed ? Motion.snappy : Motion.panel, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
#endif
