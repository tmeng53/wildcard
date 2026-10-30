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

/// Where the check-in capsules land: on an arc above the 打卡 button, spread or stacked when the
/// words are too wide for the arc.
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

    /// A rectangle by its center, relative to the button's center.
    public struct Box: Equatable, Sendable {
        public var midX: Double
        public var midY: Double
        public var width: Double
        public var height: Double

        public init(midX: Double, midY: Double, width: Double, height: Double) {
            (self.midX, self.midY, self.width, self.height) = (midX, midY, width, height)
        }

        /// Whether the two share any area once `gap` is kept between them.
        public func collides(with other: Box, gap: Double = 0) -> Bool {
            abs(midX - other.midX) < (width + other.width) / 2 + gap
                && abs(midY - other.midY) < (height + other.height) / 2 + gap
        }
    }

    /// Each capsule's center, in `kinds` order (all four unless some are left out), for capsules
    /// of the measured `widths` and one `height`, around a button of `button` size, on a screen
    /// `available` wide whose center is the button's. The arc is kept as far as the words allow:
    /// the two on top move apart, the two at the sides stay off the edges. When the arc can't
    /// hold them without touching each other, the button or the screen's edge, they stand in
    /// rows above the button instead, as many to a row as fit. Fewer kinds share the same arc,
    /// evenly.
    public static func positions(
        kinds: [CheckInKind] = CheckInKind.allCases, widths: [Double], height: Double,
        button: (width: Double, height: Double), available: Double, gap: Double = Space.xs,
        margin: Double = Space.m
    ) -> [(x: Double, y: Double)] {
        guard widths.count == kinds.count else { return arc(for: kinds) }
        let reach = available / 2 - margin
        let arc = arcPositions(kinds: kinds, widths: widths, gap: gap, reach: reach)
        let buttonBox = Box(midX: 0, midY: 0, width: button.width, height: button.height)
        let boxes = zip(arc, widths).map { Box(midX: $0.0.x, midY: $0.0.y, width: $0.1, height: height) }
        let arcFits =
            boxes.indices.allSatisfy { index in
                abs(boxes[index].midX) + boxes[index].width / 2 <= reach + 0.001
                    && !boxes[index].collides(with: buttonBox, gap: gap)
                    && boxes.indices.dropFirst(index + 1).allSatisfy {
                        !boxes[index].collides(with: boxes[$0], gap: gap)
                    }
            }
        return arcFits ? arc : rows(widths: widths, height: height, button: button, gap: gap, reach: reach)
    }

    /// The arc's spots before any measuring: each kind's own angle when all four show, else
    /// evenly between the outermost two.
    public static func arc(for kinds: [CheckInKind]) -> [(x: Double, y: Double)] {
        guard kinds != CheckInKind.allCases else { return kinds.map { offset(for: $0) } }
        let (first, last) = (angle(for: .trained), angle(for: .disclaimer))
        return kinds.indices.map { index in
            let share = kinds.count > 1 ? Double(index) / Double(kinds.count - 1) : 0.5
            let radians = (first + (last - first) * share) * Double.pi / 180
            return (radius * cos(radians), -radius * sin(radians))
        }
    }

    private static func arcPositions(kinds: [CheckInKind], widths: [Double], gap: Double, reach: Double)
        -> [(x: Double, y: Double)]
    {
        var spots = arc(for: kinds)
        // The two on top: apart by their own widths if the arc leaves them closer than that.
        if spots.count == 4 {
            let (left, right) = (1, 2)
            if spots[right].x - spots[left].x < (widths[left] + widths[right]) / 2 + gap {
                let total = widths[left] + gap + widths[right]
                spots[left].x = -total / 2 + widths[left] / 2
                spots[right].x = total / 2 - widths[right] / 2
            }
        }
        for index in spots.indices {
            let edge = reach - widths[index] / 2
            spots[index].x = min(max(spots[index].x, -edge), edge)
        }
        return spots
    }

    /// Rows above the button: the sides first, as many to a row as fit, in the arc's order.
    private static func rows(
        widths: [Double], height: Double, button: (width: Double, height: Double), gap: Double, reach: Double
    ) -> [(x: Double, y: Double)] {
        let last = widths.count - 1
        let order = last > 0 ? [0, last] + Array(1..<last) : [0]
        var rowsOfIndices: [[Int]] = []
        for member in order {
            if let last = rowsOfIndices.last,
                (last + [member]).map({ widths[$0] }).reduce(0, +) + gap * Double(last.count) <= 2 * reach
            {
                rowsOfIndices[rowsOfIndices.count - 1].append(member)
            } else {
                rowsOfIndices.append([member])
            }
        }
        var spots = [(x: Double, y: Double)](repeating: (0, 0), count: widths.count)
        for (row, members) in rowsOfIndices.enumerated() {
            let y = -(button.height / 2 + gap + height / 2 + Double(row) * (height + gap))
            let left = members.sorted()
            let total = left.map { widths[$0] }.reduce(0, +) + gap * Double(left.count - 1)
            var cursor = -total / 2
            for member in left {
                spots[member] = (cursor + widths[member] / 2, y)
                cursor += widths[member] + gap
            }
        }
        return spots
    }
}
