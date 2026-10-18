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
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// The press every Wildcard button shares. With Reduce Motion on, the control doesn't shrink.
struct PressFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? Motion.pressedScale : 1)
            .animation(
                .wildcard(isPressed ? Motion.snappy : Motion.panel, reduceMotion: reduceMotion), value: isPressed)
    }
}
#endif
