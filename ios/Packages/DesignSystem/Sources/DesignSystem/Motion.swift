import Foundation

/// A spring in SwiftUI's terms: how long it takes to settle and how much it overshoots.
/// Named apart from SwiftUI's own `Spring`, which would make the name ambiguous.
public struct MotionSpring: Sendable, Hashable {
    /// Seconds to complete one oscillation, roughly the time to settle.
    public let response: Double
    /// 1 settles with no overshoot; lower bounces more.
    public let dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }
}

/// Motion tokens. Everything that moves uses one of these, so the app feels like one thing.
public enum Motion {
    /// Taps, toggles and selection: quick, barely any overshoot.
    public static let snappy = MotionSpring(response: 0.3, dampingFraction: 0.86)
    /// Check-in capsules flying out of the 打卡 button and back: quick, with a visible bounce.
    public static let burst = MotionSpring(response: 0.24, dampingFraction: 0.6)
    /// Glass cards, speech bubbles and a pressed control springing back.
    public static let panel = MotionSpring(response: 0.37, dampingFraction: 0.52)
    /// Celebrations (a check-in landing, a medal dropping): visible bounce.
    public static let bouncy = MotionSpring(response: 0.5, dampingFraction: 0.6)
    /// Sheets, layout, scene and tab changes: no overshoot.
    public static let smooth = MotionSpring(response: 0.45, dampingFraction: 1)

    /// How far a pressed control shrinks.
    public static let pressedScale: Double = 0.96
    /// Delay between list items that enter one after another, in seconds.
    public static let stagger: Double = 0.05
    /// Delay between check-in capsules bursting out, in seconds.
    public static let burstStagger: Double = 0.028
    /// Capsules folding back into the button: a short ease-in, in seconds, in reverse order.
    public static let collapseDuration: Double = 0.19
    public static let collapseStagger: Double = 0.016
    /// With Reduce Motion on, motion becomes a short fade of this length, in seconds.
    public static let reducedDuration: Double = 0.2

    public static let all: [(name: String, spring: MotionSpring)] = [
        ("snappy", snappy), ("burst", burst), ("panel", panel), ("bouncy", bouncy), ("smooth", smooth),
    ]
}

/// Where the check-in capsules land: on an arc above the 打卡 button.
public enum BurstLayout {
    /// Distance from the button's center to each capsule's center, in points.
    public static let radius: Double = 128

    /// The capsule's angle in degrees, counterclockwise from the right.
    public static func angle(for meaning: Meaning) -> Double {
        switch meaning {
        case .trained: 162
        case .healthyMeal: 118
        case .cheatMeal: 62
        case .disclaimer: 18
        }
    }

    /// A capsule's center relative to the button's center, in screen coordinates (y grows down).
    public static func offset(for meaning: Meaning) -> (x: Double, y: Double) {
        let radians = angle(for: meaning) * Double.pi / 180
        return (radius * cos(radians), -radius * sin(radians))
    }
}
