/// An arm tucked behind its body's cloth at its seam. An arm's art starts in a round around
/// its pivot, which sits on the body, and the round turns in place: drawn over the body, a
/// sleeve's round would stay on the chest as a patch of sleeve when the arm lifts, and a bare
/// shoulder would cover what the body wears. A real sleeve is sewn to the body along a seam,
/// so the arm is drawn in two pieces that always meet there: behind its seam it lies under
/// the body's art (the body's cloth covers a sleeve's round; a sleeveless top's armhole shows
/// the bare shoulder), and in front of it over everything the body wears. Nothing swaps as
/// the arm moves, and the chest shows only the body's cloth and what it wears.
public struct Tuck: Hashable, Sendable {
    /// The arm's art is drawn over the body in front of this line, in the arm's own coordinates.
    public let seam: Line
    /// And under the body behind this one, which laps a little past the seam so no hairline
    /// shows where the two pieces meet.
    public let under: Line

    /// A line through `point`; `back` is the unit vector to the side that is not drawn.
    public struct Line: Hashable, Sendable {
        public let point: Point
        public let back: Point

        /// Whether `spot` is on the side that stays.
        public func keeps(_ spot: Point) -> Bool {
            (spot.x - point.x) * back.x + (spot.y - point.y) * back.y <= 0
        }

        /// The side that stays as a square reaching `far` from the point, for a clip.
        public func kept(reaching far: Double) -> [Point] {
            let along = Point(x: -back.y * far, y: back.x * far)
            let front = Point(x: -back.x * far, y: -back.y * far)
            return [
                Point(x: point.x + along.x, y: point.y + along.y),
                Point(x: point.x + along.x + front.x, y: point.y + along.y + front.y),
                Point(x: point.x - along.x + front.x, y: point.y - along.y + front.y),
                Point(x: point.x - along.x, y: point.y - along.y),
            ]
        }
    }

    static let lap = 0.6

    /// Nil for a seam with no length. The seam's back is the pivot's side of it.
    public init?(pivot: Point, seam: Rig.Seam) {
        let (alongX, alongY) = (seam.armpit.x - seam.top.x, seam.armpit.y - seam.top.y)
        let length = (alongX * alongX + alongY * alongY).squareRoot()
        guard length > 0 else { return nil }
        var back = Point(x: -alongY / length, y: alongX / length)
        if (pivot.x - seam.top.x) * back.x + (pivot.y - seam.top.y) * back.y < 0 {
            back = Point(x: -back.x, y: -back.y)
        }
        self.seam = Line(point: seam.top, back: back)
        under = Line(
            point: Point(x: seam.top.x - back.x * Self.lap, y: seam.top.y - back.y * Self.lap),
            back: Point(x: -back.x, y: -back.y))
    }

}
