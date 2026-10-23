import AvatarDomain

/// 上场, timed: the squad turns to look, the new member runs in from the right and jumps onto
/// their spot, then the teammates cheer one after another, nearest first, each with a line in a
/// bubble that stays long enough to read and never covers another. Then home's card drops in.
/// Seconds count from when the screen appears; the screen reads the clock and asks.
public struct EntranceScript: Hashable, Sendable {
    /// A teammate on the scene: where their feet are and how tall their head stands, in points.
    public struct Teammate: Hashable, Sendable {
        public let feet: Point
        /// From the feet to just above the head, where the bubble's tail points.
        public let height: Double

        public init(feet: Point, height: Double) {
            (self.feet, self.height) = (feet, height)
        }
    }

    /// The squad turns to look at where the new member comes in.
    public static let look = 0.25
    /// The entrance clip starts: the run in from off screen, which reaches the screen's edge
    /// about 0.3 seconds in, just after the squad turns.
    public static let run = 0.0
    /// Into the entrance clip, the feet leave the floor for the jump (its root starts to rise).
    public static let takeoffInClip = 1.7
    /// Into the entrance clip, the feet touch the spot (its root comes back to the floor).
    public static let landingInClip = 2.2
    /// The feet touch the spot: the haptic, the ring, the shockwave, the confetti.
    public static let land = run + landingInClip
    /// The new member's own cheer and line follow the landing by this much.
    public static let myLineDelay = 0.2
    /// The first teammate cheers this long after the landing, then the next every `stagger`.
    public static let firstCheer = 0.3
    public static let stagger = 0.15
    /// How long a line stays up, long enough to read a ten-character line twice.
    public static let lineDuration = 4.2
    /// Home's card drops in once the moment has landed.
    public static let cardDrop = land + 0.45
    /// The 打卡 button and the tab bar rise from the bottom.
    public static let chromeRise = land + 0.6
    /// The squad's week count turns over to include the new member's plan.
    public static let countFlip = land + 0.95
    /// The new member's head pops into the card's last ring.
    public static let myHeadPop = land + 1.05

    public let spot: Point
    public let teammates: [Teammate]
    /// When each teammate cheers, in `teammates`' order.
    public let cheers: [Double]

    public init(spot: Point, teammates: [Teammate]) {
        self.spot = spot
        self.teammates = teammates
        let nearestFirst = teammates.indices.sorted {
            Self.distance(teammates[$0].feet, spot) < Self.distance(teammates[$1].feet, spot)
        }
        var cheers = Array(repeating: 0.0, count: teammates.count)
        for (rank, index) in nearestFirst.enumerated() {
            cheers[index] = Self.land + Self.firstCheer + Double(rank) * Self.stagger
        }
        self.cheers = cheers
    }

    /// When the new member's line goes up.
    public var myLine: Double { Self.land + Self.myLineDelay }

    /// When the whole thing has played: the last line has been up its full time.
    public var end: Double {
        max(myLine, cheers.max() ?? 0) + Self.lineDuration
    }

    /// Where each line's bubble sits, its tail's point above the speaker's head: the new
    /// member's first, then the teammates' in `teammates`' order. `sizes`, in the same order,
    /// are the bubbles' measured sizes; `width` is the screen's. Bubbles go up in the order they
    /// appear, each above its own speaker, kept on screen, and moved up until it covers none
    /// placed before it.
    public func bubbles(sizes: [(width: Double, height: Double)], myHeight: Double, width: Double) -> [Point] {
        let anchors =
            [Point(x: spot.x, y: spot.y - myHeight)] + teammates.map { Point(x: $0.feet.x, y: $0.feet.y - $0.height) }
        let times = [myLine] + cheers
        let order = anchors.indices.sorted { times[$0] < times[$1] }
        var placed: [(center: Point, width: Double, height: Double)] = []
        var result = anchors
        for index in order where index < sizes.count {
            let size = sizes[index]
            let half = size.width / 2
            var point = Point(
                x: min(max(anchors[index].x, half + Self.margin), width - half - Self.margin), y: anchors[index].y)
            // `point` is the tail's tip; the bubble stands above it.
            func covers(_ other: (center: Point, width: Double, height: Double)) -> Bool {
                let center = Point(x: point.x, y: point.y - size.height / 2)
                return abs(other.center.x - center.x) < (other.width + size.width) / 2 + Self.gap
                    && abs(other.center.y - center.y) < (other.height + size.height) / 2 + Self.gap
            }
            while placed.contains(where: covers) { point.y -= Self.nudge }
            placed.append((Point(x: point.x, y: point.y - size.height / 2), size.width, size.height))
            result[index] = point
        }
        return result
    }

    /// Room kept between a bubble and the screen's edge, and between two bubbles.
    static let margin = 8.0
    static let gap = 4.0
    /// How far a bubble moves up each time it still covers another.
    static let nudge = 2.0

    private static func distance(_ first: Point, _ second: Point) -> Double {
        let (across, down) = (first.x - second.x, first.y - second.y)
        return (across * across + down * down).squareRoot()
    }
}
