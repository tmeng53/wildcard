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
    /// Celebrations (a check-in landing, a medal dropping): visible bounce.
    public static let bouncy = MotionSpring(response: 0.5, dampingFraction: 0.6)
    /// Sheets, layout and scene changes: no overshoot.
    public static let smooth = MotionSpring(response: 0.45, dampingFraction: 1)

    /// How far a pressed control shrinks.
    public static let pressedScale: Double = 0.96
    /// Delay between items that enter one after another, in seconds.
    public static let stagger: Double = 0.05
    /// With Reduce Motion on, motion becomes a short fade of this length, in seconds.
    public static let reducedDuration: Double = 0.2

    public static let all: [(name: String, spring: MotionSpring)] = [
        ("snappy", snappy), ("bouncy", bouncy), ("smooth", smooth),
    ]
}
