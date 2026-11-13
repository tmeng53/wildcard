import Foundation

/// An arm bent at its elbow by some degrees, clockwise: how to redraw the arm's own art for
/// it. Art past the elbow turns with the forearm, art before it stays with the upper arm,
/// and the art between them turns partway, more the nearer the hand, so the arm's line
/// curves through the elbow as one soft arm. Each curve is refitted through its turned
/// points, so a stroke stays smooth; the parts the arm carries (a prop, its grip) turn
/// with the forearm whole (`Figure.layout`).
public struct Bend: Hashable, Sendable {
    /// The shoulder: the arm part's pivot.
    public let shoulder: Point
    public let elbow: Rig.Elbow
    public let degrees: Double

    /// Where along the arm, from shoulder (0) to hand (1), the bend starts and is complete,
    /// around the elbow. A short sleeve ends before it starts, and a long sleeve's cuff
    /// after it is complete, so both stay whole and only the arm between curves.
    static let span = (start: -0.15, end: 0.25)

    public init(shoulder: Point, elbow: Rig.Elbow, degrees: Double) {
        (self.shoulder, self.elbow, self.degrees) = (shoulder, elbow, degrees)
    }

    /// The forearm's turn around the elbow, which whatever the arm carries follows.
    public var forearm: Transform {
        Transform.translation(x: -elbow.point.x, y: -elbow.point.y)
            .then(.rotation(degrees: degrees))
            .then(.translation(x: elbow.point.x, y: elbow.point.y))
    }

    /// A point of the arm's art moved by the bend.
    public func apply(to point: Point) -> Point {
        let turn = degrees * weight(point)
        guard turn != 0 else { return point }
        let radians = turn * .pi / 180
        let (sine, cosine) = (sin(radians), cos(radians))
        let (across, down) = (point.x - elbow.point.x, point.y - elbow.point.y)
        return Point(
            x: elbow.point.x + cosine * across - sine * down, y: elbow.point.y + sine * across + cosine * down)
    }

    /// How much of the bend a point takes: 0 on the upper arm, 1 on the forearm, easing
    /// between around the elbow.
    func weight(_ point: Point) -> Double {
        let (axisX, axisY) = (elbow.hand.x - shoulder.x, elbow.hand.y - shoulder.y)
        let length = axisX * axisX + axisY * axisY
        guard length > 0 else { return 1 }
        let along = { (spot: Point) in ((spot.x - shoulder.x) * axisX + (spot.y - shoulder.y) * axisY) / length }
        let fraction = (along(point) - along(elbow.point) - Self.span.start) / (Self.span.end - Self.span.start)
        let clamped = min(max(fraction, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// A path of the arm's art, bent. Lines keep their ends' new places; a curve passes
    /// through its own points bent (its middle, or its thirds), so it bends smoothly rather
    /// than kinking where its control points turned by different amounts.
    public func apply(to path: [PathElement]) -> [PathElement] {
        guard degrees != 0 else { return path }
        var bent: [PathElement] = []
        bent.reserveCapacity(path.count)
        var current = Point(x: 0, y: 0)
        var start = current
        for element in path {
            switch element {
            case .move(let point):
                (current, start) = (point, point)
                bent.append(.move(apply(to: point)))
            case .line(let end):
                current = end
                bent.append(.line(apply(to: end)))
            case .quadCurve(let end, let control):
                for piece in pieces([current, control, end]) {
                    let middle = quadratic(piece[0], piece[1], piece[2], at: 0.5)
                    let (from, onto, through) = (apply(to: piece[0]), apply(to: piece[2]), apply(to: middle))
                    let fitted = Point(
                        x: 2 * through.x - (from.x + onto.x) / 2, y: 2 * through.y - (from.y + onto.y) / 2)
                    bent.append(.quadCurve(end: onto, control: fitted))
                }
                current = end
            case .curve(let end, let control1, let control2):
                for piece in pieces([current, control1, control2, end]) {
                    let first = apply(to: cubic(piece[0], piece[1], piece[2], piece[3], at: 1.0 / 3))
                    let second = apply(to: cubic(piece[0], piece[1], piece[2], piece[3], at: 2.0 / 3))
                    let (from, onto) = (apply(to: piece[0]), apply(to: piece[3]))
                    // The cubic through both ends and both thirds: B(1/3) = (8P0 + 12P1 + 6P2 + P3) / 27,
                    // B(2/3) = (P0 + 6P1 + 12P2 + 8P3) / 27, solved for P1 and P2.
                    let partA = Point(x: 27 * first.x - 8 * from.x - onto.x, y: 27 * first.y - 8 * from.y - onto.y)
                    let partB = Point(x: 27 * second.x - from.x - 8 * onto.x, y: 27 * second.y - from.y - 8 * onto.y)
                    bent.append(
                        .curve(
                            end: onto,
                            control1: Point(x: (2 * partA.x - partB.x) / 18, y: (2 * partA.y - partB.y) / 18),
                            control2: Point(x: (2 * partB.x - partA.x) / 18, y: (2 * partB.y - partA.y) / 18)))
                }
                current = end
            case .close:
                current = start
                bent.append(.close)
            }
        }
        return bent
    }

    /// A curve, as its points, cut where it leaves the upper arm, so a piece on the upper arm
    /// stays as drawn: refitted whole, a curve from the shoulder to the hand would turn at the
    /// shoulder too, where the arm meets the body.
    private func pieces(_ points: [Point]) -> [[Point]] {
        let (axisX, axisY) = (elbow.hand.x - shoulder.x, elbow.hand.y - shoulder.y)
        let length = axisX * axisX + axisY * axisY
        guard length > 0 else { return [points] }
        let along = { (spot: Point) in ((spot.x - shoulder.x) * axisX + (spot.y - shoulder.y) * axisY) / length }
        let edge = along(elbow.point) + Self.span.start
        // A curve lies within its points, so one whose points are all on one side never crosses.
        let behind = points.count { along($0) - edge < 0 }
        guard behind != 0, behind != points.count else { return [points] }
        let side = { (time: Double) in along(Self.point(points, at: time)) - edge }
        // Where it crosses: a change of side between two of 16 steps, narrowed down.
        var cuts: [Double] = []
        for step in 0..<16 {
            var (low, high) = (Double(step) / 16, Double(step + 1) / 16)
            guard (side(low) < 0) != (side(high) < 0) else { continue }
            for _ in 0..<40 {
                let middle = (low + high) / 2
                if (side(low) < 0) == (side(middle) < 0) { low = middle } else { high = middle }
            }
            cuts.append((low + high) / 2)
        }
        var (rest, done, out) = (points, 0.0, [[Point]]())
        for cut in cuts {
            let (head, tail) = Self.split(rest, at: (cut - done) / (1 - done))
            out.append(head)
            (rest, done) = (tail, cut)
        }
        return out + [rest]
    }

    /// A Bézier curve's point at `time`, by de Casteljau.
    private static func point(_ points: [Point], at time: Double) -> Point {
        split(points, at: time).0.last ?? points[0]
    }

    /// A Bézier curve cut at `time` into two of the same degree, by de Casteljau.
    private static func split(_ points: [Point], at time: Double) -> ([Point], [Point]) {
        var (row, head, tail) = (points, [Point](), [Point]())
        while let first = row.first, let last = row.last {
            head.append(first)
            tail.insert(last, at: 0)
            row = zip(row, row.dropFirst()).map { from, onto in
                Point(x: from.x + (onto.x - from.x) * time, y: from.y + (onto.y - from.y) * time)
            }
        }
        return (head, tail)
    }

    private func quadratic(_ from: Point, _ control: Point, _ end: Point, at time: Double) -> Point {
        let rest = 1 - time
        return Point(
            x: rest * rest * from.x + 2 * rest * time * control.x + time * time * end.x,
            y: rest * rest * from.y + 2 * rest * time * control.y + time * time * end.y)
    }

    private func cubic(_ from: Point, _ first: Point, _ second: Point, _ end: Point, at time: Double) -> Point {
        let rest = 1 - time
        let weights = (rest * rest * rest, 3 * rest * rest * time, 3 * rest * time * time, time * time * time)
        return Point(
            x: weights.0 * from.x + weights.1 * first.x + weights.2 * second.x + weights.3 * end.x,
            y: weights.0 * from.y + weights.1 * first.y + weights.2 * second.y + weights.3 * end.y)
    }
}

extension BoundClip {
    /// An arm the clip swings without bending: its forearm trails the swing a moment behind
    /// and straightens once it stops, so every pose the clip holds stays as it was drawn.
    struct FollowThrough: Sendable {
        /// How far behind the forearm trails, in seconds.
        static let lag = 0.09
        /// How much of the swing over that moment the forearm bends by.
        static let give = 0.9
        /// The most it bends, in degrees, so a fast swing never folds the arm.
        static let most = 35.0

        let arm: Int
        let swing: Clip.Track
        /// The parts the arm carries, which keep their own angle.
        let carried: [Int]

        func bend(at time: Double, of clip: Clip) -> Double {
            var earlier = time - Self.lag
            /// A one-shot straightens over its last moment, so it ends at rest and hands back to idle.
            var settle = 1.0
            if clip.loops {
                earlier = earlier.truncatingRemainder(dividingBy: clip.duration)
                if earlier < 0 { earlier += clip.duration }
            } else {
                earlier = max(earlier, 0)
                settle = min(max((clip.duration - time) / Self.lag, 0), 1)
            }
            let trail = Self.give * (swing.value(at: earlier) - swing.value(at: time)) * settle
            return min(max(trail, -Self.most), Self.most)
        }
    }
}
