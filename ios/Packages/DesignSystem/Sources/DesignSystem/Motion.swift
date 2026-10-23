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

/// A timed ease: a cubic Bézier from rest to rest over `duration` seconds, for motion that has to
/// land at a set time rather than settle like a spring.
public struct MotionCurve: Sendable, Hashable {
    public let duration: Double
    /// The curve's two control points, as in CSS's `cubic-bezier()`.
    public let controlPoints: [Double]

    public init(duration: Double, _ firstX: Double, _ firstY: Double, _ secondX: Double, _ secondY: Double) {
        (self.duration, controlPoints) = (duration, [firstX, firstY, secondX, secondY])
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
    /// The 「+1」 over a character who just checked in: how high it rises, in points, and how long
    /// it stays, in seconds.
    public static let plusOneRise: Double = 44
    public static let plusOneDuration: Double = 1.1
    /// A speech bubble stays this long, in seconds, then fades out over `speechFade`; when the
    /// squad celebrates, each bubble starts `speechStagger` after the last.
    public static let speechHold: Double = 1.6
    public static let speechFade: Double = 0.2
    public static let speechStagger: Double = 0.06
    /// Text and a button revealing themselves on the open screen: an ease-out cubic
    /// (1 - (1 - k)³) over 0.3 s, rising `revealRise` points, each `revealStagger` after the last.
    public static let reveal = MotionCurve(duration: 0.3, 0.33, 1, 0.68, 1)
    public static let revealRise: Double = 8
    public static let revealStagger: Double = 0.08
    /// Something already in place fading in, evenly over 0.25 s.
    public static let fadeIn = MotionCurve(duration: 0.25, 0, 0, 1, 1)
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
