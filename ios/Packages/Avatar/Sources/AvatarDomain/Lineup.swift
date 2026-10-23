import Foundation

/// 排队入场: a squad along the edge of a screen, such as the foot of the 战报's last page or
/// the invite page. Up to `rowLimit` members stand in one row, centered; more walk through
/// in a queue that loops, coming in from the right and leaving on the left with a small hop.
/// Lengths are in points at the design's figure height of 96 (`scaled(by:)` for others); the
/// caller passes the time, so the walk is a pure function of it.
public struct Lineup: Hashable, Sendable {
    /// Where one member's figure is this moment: its left edge and how far it is lifted.
    public struct Spot: Hashable, Sendable {
        /// The left edge of the figure's frame, from the strip's left edge.
        public let left: Double
        /// How far above the strip's floor the figure is, mid-hop (0 on the ground).
        public let lift: Double
    }

    /// The most members who stand in a row; more walk through.
    public static let rowLimit = 5

    public let count: Int
    /// The strip's width.
    public let width: Double
    /// The figure's frame: 72 × 96 at the design size, the rig's 3:4.
    public let figureWidth: Double
    /// From one walker to the next, how fast the queue walks, and how high each step hops.
    public let gap, pace, hop: Double

    /// The design's strip (approved 2026-10-22): 72 × 96 figures, walkers 78 apart at 30 per
    /// second, hopping 5.
    public init(count: Int, width: Double) {
        self.init(count: count, width: width, figureWidth: 72, gap: 78, pace: 30, hop: 5)
    }

    private init(count: Int, width: Double, figureWidth: Double, gap: Double, pace: Double, hop: Double) {
        self.count = max(0, count)
        self.width = width
        self.figureWidth = figureWidth
        self.gap = gap
        self.pace = pace
        self.hop = hop
    }

    /// The same strip for figures `factor` times the design's size.
    public func scaled(by factor: Double) -> Lineup {
        Lineup(
            count: count, width: width, figureWidth: figureWidth * factor, gap: gap * factor,
            pace: pace * factor, hop: hop * factor)
    }

    /// Whether this many members walk through instead of standing in a row.
    public var walks: Bool { count > Self.rowLimit }

    /// Each member's spot at `time` seconds, in the order given: the row side by side, figure
    /// against figure, centered on the strip; the queue in that order from the left.
    public func spots(at time: Double) -> [Spot] {
        guard walks else {
            let middle = Double(count - 1) / 2
            return (0..<count).map { index in
                Spot(left: width / 2 - figureWidth / 2 + (Double(index) - middle) * figureWidth, lift: 0)
            }
        }
        // At least a strip and a walker long, so a walker always comes back in past the right
        // edge, however wide the screen.
        let loop = max(Double(count) * gap, width + gap)
        return (0..<count).map { index in
            let along = Double(index) * gap - time * pace
            let wrapped = (along.truncatingRemainder(dividingBy: loop) + loop).truncatingRemainder(dividingBy: loop)
            // 2.4 hops a second, each member a little out of step with the one before.
            let lift = abs(sin((time + Double(index) * 0.37) * .pi * 2.4)) * hop
            return Spot(left: wrapped - gap, lift: lift)
        }
    }

    /// Everyone standing still, for Reduce Motion: the row as it stands, or the queue stopped
    /// with as many walkers as fit on the strip centered on it and the rest past its right edge.
    public var rest: [Spot] {
        guard walks else { return spots(at: 0) }
        let fits = max(1, Int(((width - figureWidth) / gap).rounded(.down)) + 1)
        let start = (width - (Double(fits - 1) * gap + figureWidth)) / 2
        return (0..<count).map { Spot(left: start + Double($0) * gap, lift: 0) }
    }
}
