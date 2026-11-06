import Foundation

/// The squad posed for a group photo in a box, such as a holiday opening's squad layer, where
/// everyone must be seen whole: nobody walks past or is cut by the box's edges. Up to
/// `rowLimit` stand in one row; more stand in two, the back row raised so its heads show
/// over the front row's, between its figures or half a figure aside. Figures keep the rig's
/// 3:4 frame, as big as the box allows, and the front row stands on the box's bottom edge,
/// centered.
public struct SquadPhoto: Hashable, Sendable {
    /// Where one member's figure stands: its frame's top-left corner in the box.
    public struct Spot: Hashable, Sendable {
        /// The member's index in the order given.
        public let member: Int
        public let left: Double
        public let top: Double
    }

    /// The most members who stand in one row.
    public static let rowLimit = 3
    /// How far the back row stands above the front row, in figure heights.
    public static let backRowRaise = 0.4

    public let figureWidth: Double
    public let figureHeight: Double
    /// Every member's spot, back row first, so drawing them in this order puts the front row
    /// in front.
    public let spots: [Spot]

    public init(count: Int, width: Double, height: Double) {
        let count = max(0, count)
        let aspect = 3.0 / 4.0
        guard count > Self.rowLimit else {
            let figureWidth = min(height * aspect, width / Double(max(count, 1)))
            let figureHeight = figureWidth / aspect
            let start = (width - Double(count) * figureWidth) / 2
            self.figureWidth = figureWidth
            self.figureHeight = figureHeight
            spots = (0..<count).map {
                Spot(member: $0, left: start + Double($0) * figureWidth, top: height - figureHeight)
            }
            return
        }
        // The front row takes the larger half; an even squad sets its rows half a figure apart.
        let front = (count + 1) / 2
        let back = count - front
        let staggered = back == front
        let rowWidths = Double(front) + (staggered ? 0.5 : 0)
        let figureWidth = min(height / (1 + Self.backRowRaise) * aspect, width / rowWidths)
        let figureHeight = figureWidth / aspect
        let frontStart = (width - rowWidths * figureWidth) / 2
        // Between the front row's figures, or (staggered) half a figure to the right of it.
        let backStart = frontStart + figureWidth / 2
        let frontTop = height - figureHeight
        let backTop = frontTop - figureHeight * Self.backRowRaise
        self.figureWidth = figureWidth
        self.figureHeight = figureHeight
        // The back row is the members after the front row, drawn first.
        let backSpots = (0..<back).map {
            Spot(member: front + $0, left: backStart + Double($0) * figureWidth, top: backTop)
        }
        let frontSpots = (0..<front).map {
            Spot(member: $0, left: frontStart + Double($0) * figureWidth, top: frontTop)
        }
        spots = backSpots + frontSpots
    }

    /// The members from the photo's left edge to its right (back and front rows woven
    /// together), for a 人浪 that runs across it: the order is the same at any size.
    public static func leftToRight(count: Int) -> [Int] {
        SquadPhoto(count: count, width: 1, height: 1).spots
            .enumerated()
            .sorted { ($0.element.left, $0.offset) < ($1.element.left, $1.offset) }
            .map(\.element.member)
    }
}
