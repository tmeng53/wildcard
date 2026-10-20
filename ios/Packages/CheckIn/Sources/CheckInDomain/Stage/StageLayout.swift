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
    case hurdles, jogging
    case swimming
    case treadmill, squatRack, dumbbells, yogaMat
    case rally, serve
    case topRope, bouldering, chalk
}

/// How the people at a station move.
public enum StationPath: Hashable, Sendable {
    /// Round and round along lanes, all at one speed and evenly spaced; they leave one side of
    /// the screen and come back on the other. Slot `i` runs in lane `i % lanes.count`.
    case loop(from: Double, to: Double, lanes: [Lap])
    /// One lane each, back and forth.
    case lanes([Lane])
    /// Up and down a column of the wall.
    case climb([Column])
    /// In place on a spot of their own.
    case spots([StagePoint])

    public struct Lap: Hashable, Sendable {
        public let y: Double
        /// 1 runs rightwards, -1 leftwards.
        public let direction: Double
    }

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
    /// Points per second along the path.
    public let speed: Double
    public let scale: Double?
}

/// Where everyone can be on one scene, in screen points after the scene's art is lifted to
/// make room for the 打卡 button. Every scene follows one plan: its own stations for people
/// whose sport matches, its playing area for anyone training while the stations are empty,
/// the open floor for everyone else, and me front and centre.
public struct StageLayout: Hashable, Sendable {
    public let stations: [Station]
    /// Which stations a sport uses, in the order they fill.
    public let stationsBySport: [Sport: [StationKind]]
    /// Spots on the playing area (the track, the court), from the middle out. Never on a wall
    /// or in the water.
    public let field: [StagePoint]
    /// Spots on the open floor, best first: front row first, then from the middle out, like a
    /// team photo. Never on equipment, walls, water or the court, and never right around me.
    public let floor: [StagePoint]
    /// Where the water is, if the scene has any; nobody in it cheers.
    public let water: ClosedRange<Double>?

    /// Me: always front and centre, just above the 打卡 button.
    public static let mySpot = StagePoint(x: 195, y: 676)
    /// How much bigger I am than the nearest teammate.
    public static let myScale = 0.28

    /// A teammate's size at a depth: nearer is bigger, from 0.17 at the back to 0.25 at the front.
    public static func scale(atDepth y: Double) -> Double {
        let near = min(1, max(0, (y - 280) / (640 - 280)))
        return 0.17 + (0.25 - 0.17) * near
    }

    init(
        stations: [Station], stationsBySport: [Sport: [StationKind]], field: [StageRect], fieldGaps: [StageRect] = [],
        open: [StageRect], props: [StageRect], water: ClosedRange<Double>? = nil
    ) {
        self.stations = stations
        self.stationsBySport = stationsBySport
        self.water = water
        self.field = Self.fieldSpots(in: field, avoiding: props + fieldGaps)
        let busy = stations.flatMap { station -> [StagePoint] in
            if case .spots(let spots) = station.path { spots } else { [] }
        }
        floor = Self.floorSpots(in: open, avoiding: props, busy: busy)
    }

    func station(_ kind: StationKind) -> Station? {
        stations.first { $0.kind == kind }
    }

    /// The playing area on an even grid, 80 apart with every other row offset half a step,
    /// nearest the middle first.
    private static func fieldSpots(in areas: [StageRect], avoiding: [StageRect]) -> [StagePoint] {
        var spots: [(StagePoint, Double)] = []
        for area in areas {
            let middle = StagePoint(x: (area.minX + area.maxX) / 2, y: (area.minY + area.maxY) / 2)
            var row = 0
            var y = area.maxY
            while y >= area.minY {
                var x = area.minX + (row.isMultiple(of: 2) ? 0 : 40)
                while x <= area.maxX {
                    let point = StagePoint(x: x, y: y)
                    if !avoiding.contains(where: { $0.blocks(point) }) {
                        let across = x - middle.x
                        let deep = (y - middle.y) * 1.3
                        spots.append((point, (across * across + deep * deep).squareRoot()))
                    }
                    x += 80
                }
                y -= 62
                row += 1
            }
        }
        return spots.enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }.map(\.element.0)
    }

    /// The open floor on a team-photo grid: rows 60 apart from the front, five across 80 apart
    /// centred on the screen, every other row offset half a step.
    private static func floorSpots(in areas: [StageRect], avoiding: [StageRect], busy: [StagePoint]) -> [StagePoint] {
        var spots: [StagePoint] = []
        for area in areas {
            var row = 0
            var y = area.maxY - 24
            while y >= area.minY {
                var x = mySpot.x + (row.isMultiple(of: 2) ? 0 : 40) - 160
                while x <= area.maxX - 18 {
                    let point = StagePoint(x: x, y: y)
                    let besideMe = abs(x - mySpot.x) < 52 && y > 600
                    let offScreen = x < 26 || x > 364
                    let onProp = avoiding.contains { $0.blocks(point) }
                    let onStation = busy.contains { spot in
                        let across = spot.x - x
                        let deep = (spot.y - y) * 1.4
                        return (across * across + deep * deep).squareRoot() < 46
                    }
                    if !besideMe && !offScreen && !onProp && !onStation {
                        spots.append(point)
                    }
                    x += 80
                }
                y -= 60
                row += 1
            }
        }
        // Front first, then the middle: a spot's worth is its depth less half its distance from centre.
        func worth(_ point: StagePoint) -> Double { point.y - abs(point.x - mySpot.x) * 0.5 }
        return spots.enumerated().sorted { (-worth($0.element), $0.offset) < (-worth($1.element), $1.offset) }
            .map(\.element)
    }
}
// swiftlint:enable identifier_name
