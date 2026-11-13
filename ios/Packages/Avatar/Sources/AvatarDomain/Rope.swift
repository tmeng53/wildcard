import Foundation

/// A rope hung between two points of a pose, such as a leash from a fist to a dog's collar: it
/// sags under its own weight while its ends are closer than its length and pulls straight once
/// they are that far apart. Its art is drawn as straight lines from one end to the other at rest
/// (`Rig.Part.rope`), and each is redrawn as this curve every frame, so the rope follows both ends
/// whatever carries them.
public struct Rope: Hashable, Sendable {
    public let from: Point
    public let to: Point
    /// The quadratic curve's control point: below the middle by twice the sag.
    public let control: Point

    /// A rope `length` long hung from `from` to `to`.
    public init(from: Point, to: Point, length: Double) {
        let reach = hypot(to.x - from.x, to.y - from.y)
        // A shallow curve's length is about its chord's plus 8/3 of its sag squared over the chord.
        let sag = reach > 0 && reach < length ? (3 * reach * (length - reach) / 8).squareRoot() : 0
        (self.from, self.to) = (from, to)
        control = Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + 2 * sag)
    }

    /// A line of the rope's art, hung: its start at `from`, its end at `to`.
    public func apply(to path: [PathElement]) -> [PathElement] {
        path.map { element in
            switch element {
            case .move: .move(from)
            case .line: .quadCurve(end: to, control: control)
            case .quadCurve, .curve, .close: element
            }
        }
    }
}

extension Rig {
    /// Where a rope part hangs from and to: a point drawn on one part and a point on another, in
    /// canvas coordinates at rest, and how much longer than the distance between them it is.
    public struct RopeEnds: Hashable, Sendable {
        public var from: Anchor
        public var to: Anchor
        public var slack: Double

        public init(from: Anchor, to: Anchor, slack: Double) {
            (self.from, self.to, self.slack) = (from, to, slack)
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
            guard let from = parts.firstIndex(where: { $0.id == ends.from.part }),
                let to = parts.firstIndex(where: { $0.id == ends.to.part }), from != index, to != index,
                parts[from].rope == nil, parts[to].rope == nil
            else { throw .invalidRope(part: part.id, problem: "its ends must be two other parts") }
            guard ends.slack >= 0 else { throw .invalidRope(part: part.id, problem: "slack is negative") }
            for shape in built[index].art.flatMap(\.shapes) {
                guard shape.path.count == 2, case .move = shape.path[0], case .line = shape.path[1] else {
                    throw .invalidRope(part: part.id, problem: "its art must be straight lines, each M x y L x y")
                }
            }
            let reach = hypot(ends.to.point.x - ends.from.point.x, ends.to.point.y - ends.from.point.y)
            built[index].rope = RopeLink(
                from: from, fromPoint: ends.from.point, to: to, toPoint: ends.to.point, length: reach + ends.slack)
        }
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
