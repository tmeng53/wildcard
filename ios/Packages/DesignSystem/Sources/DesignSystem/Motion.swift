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

    /// The same spring, leaving: exits run a fifth faster than entrances.
    public var exit: MotionSpring {
        MotionSpring(response: response * Motion.exitFactor, dampingFraction: dampingFraction)
    }
}

/// Motion tokens: four everyday springs that never bounce, and one bounce kept for the moment a
/// check-in lands. Everything that moves uses one of these, so the app feels like one thing.
public enum Motion {
    /// Every button while it is held and as it lets go.
    public static let press = MotionSpring(response: 0.17, dampingFraction: 0.9)
    /// Selection and switches changing color: no overshoot.
    public static let change = MotionSpring(response: 0.10, dampingFraction: 1)
    /// Panels and anything that opens in place: the check-in capsules, a speech bubble.
    public static let sheet = MotionSpring(response: 0.24, dampingFraction: 0.9)
    /// Page changes and layout: scenes, tabs, steps.
    public static let page = MotionSpring(response: 0.36, dampingFraction: 0.9)
    /// The check-in landing: the only spring that visibly bounces.
    public static let celebrate = MotionSpring(response: 0.5, dampingFraction: 0.6)

    /// Exits run this fraction of their entrance's time.
    public static let exitFactor: Double = 0.8
    /// How far a pressed control shrinks.
    public static let pressedScale: Double = 0.96
    /// Delay between items that enter one after another, in seconds.
    public static let stagger: Double = 0.05
    /// Delay between check-in capsules opening, in seconds.
    public static let burstStagger: Double = 0.028
    /// Capsules folding back into the button: a short ease-in, in seconds, in reverse order.
    public static let collapseDuration: Double = 0.19
    public static let collapseStagger: Double = 0.016
    /// A status ring drawing itself closed, fast then slow, in seconds.
    public static let ringFill: Double = 0.5
    /// How far the avatar pops when its ring closes, on `celebrate`.
    public static let ringPopScale: Double = 1.08
    /// With Reduce Motion on, motion becomes a fade of this length, in seconds.
    public static let reducedDuration: Double = 0.2

    public static let all: [(name: String, spring: MotionSpring)] = [
        ("press", press), ("change", change), ("sheet", sheet), ("page", page), ("celebrate", celebrate),
    ]
}

/// Where the check-in capsules land: on an arc above the 打卡 button.
public enum BurstLayout {
    /// Distance from the button's center to each capsule's center, in points.
    public static let radius: Double = 128

    /// The capsule's angle in degrees, counterclockwise from the right.
    public static func angle(for kind: CheckInKind) -> Double {
        switch kind {
        case .trained: 162
        case .healthyMeal: 118
        case .cheatMeal: 62
        case .disclaimer: 18
        }
    }

    /// A capsule's center relative to the button's center, in screen coordinates (y grows down).
    public static func offset(for kind: CheckInKind) -> (x: Double, y: Double) {
        let radians = angle(for: kind) * Double.pi / 180
        return (radius * cos(radians), -radius * sin(radians))
    }
}
