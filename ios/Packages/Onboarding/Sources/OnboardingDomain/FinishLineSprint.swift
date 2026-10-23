import AvatarDomain
import Foundation

/// The open screen's first moment: WILDCARD sprints in from the left, leaning into it, brakes,
/// dips at the line and breaks the finish tape, which falls away and fades. The word ends where
/// it stands on the still screen. Everything runs in fixed steps from the layout alone, so the
/// same screen plays the same sprint and the break's time is known before it plays.
public struct FinishLineSprint: Sendable {
    /// Where the word and the floor are on screen, in points.
    public struct Layout: Hashable, Sendable {
        /// The word's right edge at rest.
        public let wordRight: Double
        /// The top of its capitals and its baseline: the tape catches between them.
        public let capTop: Double
        public let baseline: Double
        /// The floor's top, where the tape hangs to and lies on once broken.
        public let floorTop: Double

        public init(wordRight: Double, capTop: Double, baseline: Double, floorTop: Double) {
            (self.wordRight, self.capTop, self.baseline, self.floorTop) = (wordRight, capTop, baseline, floorTop)
        }

        /// Halfway up the capitals: where the tape snaps.
        var middle: Double { (capTop + baseline) / 2 }
    }

    /// One step of the simulation, in seconds.
    public static let step = 1.0 / 240
    /// The tape fades out over this time, starting this long after the break.
    static let fadeDelay = 0.45
    static let fadeDuration = 0.3

    public let layout: Layout
    /// Seconds since the sprint started.
    public private(set) var time = 0.0
    /// How far left of its place the word is drawn (negative while it runs in).
    public private(set) var offset: Double
    /// How far up its stride lifts it (negative is up).
    public private(set) var lift = 0.0
    /// Its lean in degrees, as a skew about its baseline: negative leans forward.
    public var lean: Double { leanSpring.value }
    /// When the tape broke, or nil before.
    public private(set) var brokeAt: Double?

    private static let speed = 900.0
    /// The word starts braking this far from its place.
    private static let brakeDistance = 90.0
    /// The brake is a critically damped spring of this period.
    private static let brakePeriod = 0.45
    private static let gravity = 3000.0

    private let tapeX: Double
    private var velocity = speed
    private var braking = false
    private var dipUntil: Double?
    private var leanSpring = Spring(value: -14, response: 0.34, damping: 0.5)
    private var tape: Rope

    public init(layout: Layout) {
        self.layout = layout
        offset = -(layout.wordRight + 24)
        tapeX = layout.wordRight - 115
        tape = Rope(from: Point(x: tapeX, y: -12), to: Point(x: tapeX, y: layout.floorTop), points: 44)
    }

    /// The tape as lines to stroke: one before the break, two after.
    public var tapePieces: [[Point]] { tape.pieces }

    /// How visible the tape is, from 1 to 0 once it has fallen.
    public var tapeOpacity: Double {
        guard let brokeAt else { return 1 }
        return 1 - min(max((time - brokeAt - Self.fadeDelay) / Self.fadeDuration, 0), 1)
    }

    /// True once the tape has gone and the word stands still at its place.
    public var isFinished: Bool {
        guard brokeAt != nil else { return false }
        return tapeOpacity == 0 && abs(offset) < 0.05 && abs(velocity) < 1 && abs(lean) < 0.05
    }

    /// When the tape breaks and when the whole sprint is over for this layout, found by playing
    /// it through, so the screen can time the haptic, the cheer and the reveal to the break.
    public static func timing(for layout: Layout) -> (breaks: Double, ends: Double) {
        var sprint = FinishLineSprint(layout: layout)
        while !sprint.isFinished, sprint.time < 5 { sprint.advance(to: sprint.time + step) }
        return (sprint.brokeAt ?? sprint.time, sprint.time)
    }

    /// Plays on to `target` seconds in whole steps.
    public mutating func advance(to target: Double) {
        while time + Self.step <= target + 1e-9 { stepOnce() }
    }

    private mutating func stepOnce() {
        let step = Self.step
        time += step
        if braking {
            let omega = 2 * Double.pi / Self.brakePeriod
            velocity += (-omega * omega * offset - 2 * omega * velocity) * step
            offset += velocity * step
        } else {
            offset += velocity * step
            if offset >= -Self.brakeDistance { braking = true }
        }
        // The dip at the line, then upright.
        if brokeAt == nil, dipUntil == nil, layout.wordRight + offset > tapeX {
            dipUntil = time + 0.08
            leanSpring.retarget(-24, response: 0.16, damping: 0.8)
        }
        if let dipUntil, time > dipUntil, leanSpring.target != 0 {
            leanSpring.retarget(0, response: 0.36, damping: 0.5)
        }
        leanSpring.advance(step)
        lift = braking ? lift * 0.85 : -5 * abs(sin(Double.pi * time / 0.14))
        let front = (slope: tan(lean * Double.pi / 180), right: layout.wordRight + offset)
        tape.advance(step, gravity: Self.gravity, floor: layout.floorTop) { point in
            guard point.y >= layout.capTop, point.y <= layout.baseline else { return point }
            let edge = front.right + front.slope * (point.y - layout.baseline) + 2
            return point.x < edge && point.x > edge - 70 ? Point(x: edge, y: point.y) : point
        }
        if brokeAt == nil, tape.farthest(rightOf: tapeX) > 16 { snap() }
    }

    /// The tape snaps level with the word's middle; the top lets go of its post, and both ends
    /// fly on with the word, the lower end most where it was hit.
    private mutating func snap() {
        brokeAt = time
        let middle = layout.middle
        let cut = tape.nearest(toHeight: middle)
        tape.cut(after: cut)
        tape.release(0)
        let span = layout.floorTop - middle
        for index in tape.points.indices where !tape.points[index].pinned {
            let force = index > cut ? min(max((layout.floorTop - tape.points[index].now.y) / span, 0), 1) : 0.6
            tape.kick(index, by: Point(x: 650 * force, y: -80 * force), over: Self.step)
        }
    }
}

/// A spring toward a target, by response (its period, in seconds) and damping ratio.
private struct Spring: Sendable {
    private(set) var value: Double
    private(set) var target: Double
    private var velocity = 0.0
    private var omega: Double
    private var damping: Double

    init(value: Double, response: Double, damping: Double) {
        (self.value, target, omega, self.damping) = (value, value, 2 * Double.pi / response, damping)
    }

    mutating func retarget(_ target: Double, response: Double, damping: Double) {
        (self.target, omega, self.damping) = (target, 2 * Double.pi / response, damping)
    }

    mutating func advance(_ step: Double) {
        velocity += (-omega * omega * (value - target) - 2 * damping * omega * velocity) * step
        value += velocity * step
    }
}

/// The finish tape: points joined by links that pull them back together (Verlet), pinned at
/// both ends to begin with.
private struct Rope: Sendable {
    struct Mass: Sendable {
        var now: Point
        var before: Point
        var pinned: Bool
    }

    struct Link: Sendable {
        let head: Int
        let tail: Int
        let length: Double
    }

    private(set) var points: [Mass]
    private var links: [Link]

    init(from start: Point, to end: Point, points count: Int) {
        points = (0..<count).map { index in
            let share = Double(index) / Double(count - 1)
            let point = Point(x: start.x + (end.x - start.x) * share, y: start.y + (end.y - start.y) * share)
            return Mass(now: point, before: point, pinned: index == 0 || index == count - 1)
        }
        let length = hypot(end.x - start.x, end.y - start.y) / Double(count - 1) * 0.985
        links = (0..<count - 1).map { Link(head: $0, tail: $0 + 1, length: length) }
    }

    var pieces: [[Point]] {
        var pieces: [[Point]] = []
        var last = -2
        for link in links {
            if link.head != last { pieces.append([points[link.head].now]) }
            pieces[pieces.count - 1].append(points[link.tail].now)
            last = link.tail
        }
        return pieces
    }

    func farthest(rightOf post: Double) -> Double {
        points.map { $0.now.x - post }.max() ?? 0
    }

    func nearest(toHeight y: Double) -> Int {
        points.indices.min { abs(points[$0].now.y - y) < abs(points[$1].now.y - y) } ?? 0
    }

    mutating func cut(after index: Int) {
        links.removeAll { $0.head == index }
    }

    mutating func release(_ index: Int) {
        points[index].pinned = false
    }

    mutating func kick(_ index: Int, by velocity: Point, over step: Double) {
        let now = points[index].now
        points[index].before = Point(x: now.x - velocity.x * step, y: now.y - velocity.y * step)
    }

    mutating func advance(_ step: Double, gravity: Double, floor: Double, collide: (Point) -> Point) {
        for index in points.indices where !points[index].pinned {
            let mass = points[index]
            let velocity = Point(x: (mass.now.x - mass.before.x) * 0.992, y: (mass.now.y - mass.before.y) * 0.992)
            points[index].before = mass.now
            points[index].now = Point(
                x: mass.now.x + velocity.x, y: mass.now.y + velocity.y + gravity * step * step)
        }
        for _ in 0..<24 {
            for link in links { pull(link) }
            for index in points.indices where !points[index].pinned {
                points[index].now = collide(points[index].now)
                if points[index].now.y > floor {
                    // On the floor it slides to a stop.
                    let mass = points[index]
                    points[index].now.y = floor
                    points[index].before.x = mass.now.x - (mass.now.x - mass.before.x) * 0.6
                }
            }
        }
    }

    private mutating func pull(_ link: Link) {
        let (head, tail) = (points[link.head], points[link.tail])
        let delta = Point(x: tail.now.x - head.now.x, y: tail.now.y - head.now.y)
        let distance = max(hypot(delta.x, delta.y), 1e-6)
        guard distance > link.length else { return }
        let excess = (distance - link.length) / distance
        let share =
            head.pinned
            ? (head: 0.0, tail: 1.0) : tail.pinned ? (head: 1.0, tail: 0.0) : (head: 0.5, tail: 0.5)
        points[link.head].now.x += delta.x * excess * share.head
        points[link.head].now.y += delta.y * excess * share.head
        points[link.tail].now.x -= delta.x * excess * share.tail
        points[link.tail].now.y -= delta.y * excess * share.tail
    }
}
