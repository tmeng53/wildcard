import Contracts

// swiftlint:disable identifier_name - x, from and to are the names a point and a lane read best with.

/// A point on the home scene, in the design's 390×844 points. The screen scales it to its width.
public struct StagePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle on the scene, in stage points.
public struct StageRect: Hashable, Sendable {
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double

    public init(x: ClosedRange<Double>, y: ClosedRange<Double>) {
        minX = x.lowerBound
        maxX = x.upperBound
        minY = y.lowerBound
        maxY = y.upperBound
    }

    /// Whether a person standing at `point` would overlap it: feet a little above, the body
    /// rising above the feet.
    func blocks(_ point: StagePoint) -> Bool {
        point.x > minX - 16 && point.x < maxX + 16 && point.y > minY - 6 && point.y < maxY + 30
    }
}

/// A piece of the scene's equipment that people whose sport matches use.
public enum StationKind: String, CaseIterable, Hashable, Sendable {
    case jogging
    case swimming
    case treadmill, squatRack, dumbbells, yogaMat
    case rally, serve
    case topRope, bouldering, chalk
}

/// How the people at a station move.
public enum StationPath: Hashable, Sendable {
    /// Back and forth along lanes, turning before the screen's edge, at `speed` points per
    /// second. Slots share the lanes in turn.
    case lanes([Lane], speed: Double)
    /// Up and down a column of the wall, at `speed` points per second.
    case climb([Column], speed: Double)
    /// In place on a spot of their own.
    case spots([StagePoint])

    public struct Lane: Hashable, Sendable {
        public let from: Double
        public let to: Double
        public let y: Double
    }

    public struct Column: Hashable, Sendable {
        public let x: Double
        public let top: Double
        public let bottom: Double
    }
}

/// One station: its kind, how many it holds, how they move, and their size if it isn't the
/// depth's (people on the climbing wall are drawn smaller, so they fit on it).
public struct Station: Hashable, Sendable {
    public let kind: StationKind
    public let capacity: Int
    public let path: StationPath
    public let scale: Double?

    /// The lane a slot moves along on `.lanes`.
    func lane(ofSlot slot: Int) -> StationPath.Lane? {
        guard case .lanes(let lanes, _) = path, !lanes.isEmpty else { return nil }
        return lanes[slot % lanes.count]
    }
}

/// Where everyone can be on one scene, in screen points after the scene's art is lifted to
/// make room for the 打卡 button. Every scene follows one plan: its own stations for people
/// whose sport matches, the rest of the scene for everyone else, scattered (the track and the
/// court included, never a wall or the water), and me front and centre.
public struct StageLayout: Hashable, Sendable {
    public let stations: [Station]
    /// Which stations a sport uses, in the order they fill.
    public let stationsBySport: [Sport: [StationKind]]
    /// Every spot someone can stand on, front row first, then from the middle out. Never on
    /// equipment, walls, water or the net, never on a station's own spot, and never right
    /// around me. `SquadStage` leaves out the ones on a lane someone is running.
    public let floor: [StagePoint]

    /// The stage's width, the screen's in the design.
    public static let width = 390.0

    /// Me: always front and centre, just above the 打卡 button.
    public static let mySpot = StagePoint(x: 195, y: 676)
    /// How much bigger I am than the nearest teammate.
    public static let myScale = 0.34

    /// How far a character's canvas stays from the screen's sides, so nobody is cut off, even
    /// while the camera leans in.
    static let edgeInset = 8.0

    /// Whether a character of `scale` with its feet at `point` is drawn whole on the screen: its
    /// 240-point canvas inside the sides by `edgeInset`.
    public static func fitsOnScreen(_ point: StagePoint, scale: Double) -> Bool {
        let half = 120 * scale
        return point.x - half >= edgeInset && point.x + half <= width - edgeInset
    }

    /// A teammate's size at a depth: nearer is bigger, from 0.21 at the back to 0.29 at the front.
    public static func scale(atDepth y: Double) -> Double {
        let near = min(1, max(0, (y - 280) / (640 - 280)))
        return 0.21 + (0.29 - 0.21) * near
    }

    /// `lines` are the depths of lines painted across the floor (a track's lane lines): whoever
    /// stands between the first and the last stands in the middle of a lane, never on a line.
    init(
        stations: [Station], stationsBySport: [Sport: [StationKind]], standing: [StageRect], props: [StageRect],
        lines: [Double] = []
    ) {
        self.stations = stations
        self.stationsBySport = stationsBySport
        let busy = stations.flatMap { station -> [StagePoint] in
            if case .spots(let spots) = station.path { spots } else { [] }
        }
        floor = Self.floorSpots(in: standing, avoiding: props, busy: busy, lines: lines.sorted())
    }

    /// The middle of the lane `y` falls in, between two of `lines`; `y` itself outside them.
    static func laneMiddle(of y: Double, between lines: [Double]) -> Double {
        for (top, bottom) in zip(lines, lines.dropFirst()) where (top...bottom).contains(y) {
            return (top + bottom) / 2
        }
        return y
    }

    /// Whether two people standing at `one` and `other` would be drawn over each other.
    static func crowds(_ one: StagePoint, _ other: StagePoint) -> Bool {
        let across = one.x - other.x
        let deep = (one.y - other.y) * 1.4
        return (across * across + deep * deep).squareRoot() < 46
    }

    func station(_ kind: StationKind) -> Station? {
        stations.first { $0.kind == kind }
    }

    /// Where people can stand, on a team-photo grid: rows 70 apart from the front (closer on a
    /// shallow floor, so three rows always fit), five across the whole width 76 apart and centred on
    /// the screen, every other row offset half a step, clear of the `busy` spots, each row in the
    /// middle of the lane it falls in.
    private static func floorSpots(
        in areas: [StageRect], avoiding: [StageRect], busy: [StagePoint], lines: [Double]
    ) -> [StagePoint] {
        // 76 rather than the spec's 80, so the outer ones aren't cut off by the screen's edge.
        let across = 76.0
        var spots: [(point: StagePoint, row: Int)] = []
        for area in areas {
            var row = 0
            var y = area.maxY - 24
            // Never under a character's width apart, so a floor too shallow for rows still ends.
            let gap = max(24, min(70, (y - area.minY) / 2))
            while y >= area.minY {
                var x = mySpot.x - across * (row.isMultiple(of: 2) ? 2 : 1.5)
                while x <= area.maxX - 30 {
                    let point = StagePoint(x: x, y: laneMiddle(of: y, between: lines))
                    let besideMe = abs(x - mySpot.x) < 60 && y > 590
                    let offScreen = !fitsOnScreen(point, scale: scale(atDepth: point.y))
                    let onProp = avoiding.contains { $0.blocks(point) }
                    let taken = busy.contains { crowds($0, point) }
                    if !besideMe && !offScreen && !onProp && !taken {
                        spots.append((point, row))
                    }
                    x += across
                }
                y -= gap
                row += 1
            }
        }
        // Front row first, then from the middle out.
        func fromMiddle(_ point: StagePoint) -> Double { abs(point.x - mySpot.x) }
        return spots.enumerated()
            .sorted {
                ($0.element.row, fromMiddle($0.element.point), $0.offset)
                    < ($1.element.row, fromMiddle($1.element.point), $1.offset)
            }
            .map(\.element.point)
    }
}
// swiftlint:enable identifier_name
