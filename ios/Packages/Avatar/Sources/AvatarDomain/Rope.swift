import Foundation

/// A rope hung between two points of a pose, such as a leash from a fist to a dog's collar: it
/// sags under its own weight while its ends are closer than its length and pulls straight once
/// they are that far apart. Its art is drawn as straight lines from one end to the other at rest
/// (`Rig.Part.rope`), and each is redrawn as this curve every frame, so the rope follows both ends
/// whatever carries them.
public struct Rope: Hashable, Sendable {
    public let start: Point
    public let end: Point
    /// The quadratic curve's control point: below the middle by twice the sag.
    public let control: Point

    /// A rope `length` long hung from `start` to `end`.
    public init(from start: Point, to end: Point, length: Double) {
        let reach = hypot(end.x - start.x, end.y - start.y)
        // A shallow curve's length is about its chord's plus 8/3 of its sag squared over the chord.
        let sag = reach > 0 && reach < length ? (3 * reach * (length - reach) / 8).squareRoot() : 0
        (self.start, self.end) = (start, end)
        control = Point(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + 2 * sag)
    }

    /// A line of the rope's art, hung: its start at `start`, its end at `end`.
    public func apply(to path: [PathElement]) -> [PathElement] {
        path.map { element in
            switch element {
            case .move: .move(start)
            case .line: .quadCurve(end: end, control: control)
            case .quadCurve, .curve, .close: element
            }
        }
    }
}

extension Rig {
    /// Where a rope part hangs from and to: a point drawn on one part and a point on another, in
    /// canvas coordinates at rest, and how much longer than the distance between them it is.
    public struct RopeEnds: Hashable, Sendable {
        public var start: Anchor
        public var end: Anchor
        public var slack: Double

        public init(start: Anchor, end: Anchor, slack: Double) {
            (self.start, self.end, self.slack) = (start, end, slack)
        }
    }

    /// A point on a part, which moves as that part does.
    public struct Anchor: Hashable, Sendable {
        public var part: PartID
        public var point: Point

        public init(part: PartID, point: Point) {
            (self.part, self.point) = (part, point)
        }
    }
}

extension Figure {
    /// Links each rope to the parts it hangs between, checking it can hang: no parent, both ends
    /// other parts, and art of straight lines only.
    static func resolveRopes(_ built: inout [Part], _ parts: [Rig.Part]) throws(AvatarError) {
        for (index, part) in parts.enumerated() {
            guard let ends = part.rope else { continue }
            guard part.parent == nil, part.elbow == nil, part.twin == nil else {
                throw .invalidRope(part: part.id, problem: "a rope has no parent, elbow or twin")
            }
            guard let start = parts.firstIndex(where: { $0.id == ends.start.part }),
                let end = parts.firstIndex(where: { $0.id == ends.end.part }), start != index, end != index,
                parts[start].rope == nil, parts[end].rope == nil
            else { throw .invalidRope(part: part.id, problem: "its ends must be two other parts") }
            guard ends.slack >= 0 else { throw .invalidRope(part: part.id, problem: "slack is negative") }
            for shape in built[index].art.flatMap(\.shapes) {
                guard shape.path.count == 2, case .move = shape.path[0], case .line = shape.path[1] else {
                    throw .invalidRope(part: part.id, problem: "its art must be straight lines, each M x y L x y")
                }
            }
            let reach = hypot(ends.end.point.x - ends.start.point.x, ends.end.point.y - ends.start.point.y)
            built[index].rope = RopeLink(
                start: start, startPoint: ends.start.point, end: end, endPoint: ends.end.point,
                length: reach + ends.slack)
        }
    }

    /// Hangs each rope between where its ends were just placed (`carriers`, past the elbow for an
    /// arm), as opaque as the fainter end.
    func hangRopes(_ placements: inout [Placement], _ carriers: [Transform], _ pose: Pose) {
        for (index, part) in parts.enumerated() {
            guard let link = part.rope else { continue }
            placements[index] = Placement(
                transform: .identity,
                opacity: pose.parts[index].opacity
                    * min(placements[link.start].opacity, placements[link.end].opacity),
                rope: Rope(
                    from: carriers[link.start].apply(to: link.startPoint),
                    to: carriers[link.end].apply(to: link.endPoint), length: link.length))
        }
    }

    /// A rope's ends as indices into `parts`, each with its point at rest, and its length.
    public struct RopeLink: Hashable, Sendable {
        public let start: Int
        public let startPoint: Point
        public let end: Int
        public let endPoint: Point
        public let length: Double
    }
}

extension Placement {
    /// A path of the part's art as this placement draws it before its transform: bent for a bent
    /// arm, hung for a rope.
    public func shaped(_ path: [PathElement]) -> [PathElement] {
        if let bend { return bend.apply(to: path) }
        if let rope { return rope.apply(to: path) }
        return path
    }
}
