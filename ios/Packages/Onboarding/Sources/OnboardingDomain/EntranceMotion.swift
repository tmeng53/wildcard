import AvatarDomain
import Foundation

/// What moves around the characters at 上场, from the clock, in the design's points on a
/// 390-point-wide stage: the jump's turn, the camera, the empty spot waiting, the shockwave on
/// landing, the dust, and the squad turning to watch. Seconds count from when the screen
/// appears, as in `EntranceScript`.
public struct EntranceMotion: Sendable {
    /// Where the new member lands, and how big they are drawn (canvas points per stage point).
    public let spot: Point
    public let scale: Double
    /// The entrance clip's root `x`, in canvas points from the spot.
    private let rootX: Clip.Track?
    /// The dust kicked up while running, skidding and landing, in the order it starts.
    public let puffs: [Puff]

    /// `entrance` is `PlaceholderCharacter.entrance()`; its root carries the character in.
    public init(spot: Point, scale: Double, entrance: Clip) {
        self.spot = spot
        self.scale = scale
        let rootX = entrance.tracks.first { $0.part == "root" && $0.channel == .x }
        self.rootX = rootX
        puffs = Self.puffs(newcomerX: { Self.x(at: $0, rootX: rootX, spot: spot, scale: scale) }, spot: spot)
    }

    /// Where the new member's feet are across the stage.
    public func newcomerX(at time: Double) -> Double {
        Self.x(at: time, rootX: rootX, spot: spot, scale: scale)
    }

    private static func x(at time: Double, rootX: Clip.Track?, spot: Point, scale: Double) -> Double {
        spot.x + (rootX?.value(at: max(time - EntranceScript.run, 0)) ?? 0) * scale
    }

    // MARK: The turn in the air

    /// Which way the new member faces, as a horizontal scale: 1 as drawn, -1 mirrored. They
    /// run and skid facing the way they go (left), then turn one and a half times in the air
    /// and land facing out (Tracy kept the turn for this one moment, 23 Oct).
    public static func facing(at time: Double) -> Double {
        let clip = time - EntranceScript.run
        if clip < EntranceScript.takeoffInClip { return -1 }
        if clip >= EntranceScript.landingInClip { return 1 }
        let progress = smooth((clip - EntranceScript.takeoffInClip) / Self.airtime)
        return -cos(progress * 3 * .pi)
    }

    private static let airtime = EntranceScript.landingInClip - EntranceScript.takeoffInClip

    // MARK: The camera

    /// The camera: a slow push in on the spot while the new member runs in, a jolt on landing,
    /// then easing back out. `zoom` scales about the spot; `shake` moves down, in points.
    public static func camera(at time: Double) -> (zoom: Double, shake: Double) {
        let land = EntranceScript.land
        let pushIn = smooth((time - 0.1) / (land - 0.7)) * Self.push
        let pullOut = smooth((time - land - 0.15) / 0.8)
        let since = time - land
        let shake = since > 0 && since < 0.3 ? sin(since * 70) * 3 * (1 - since / 0.3) : 0
        return (1 + pushIn * (1 - pullOut), shake)
    }

    /// How far the camera pushes in.
    static let push = 0.07

    // MARK: The spot, the ring and the shockwave

    /// The empty spot's dashed mark: fading in, breathing while it waits, gone as the new
    /// member lands on it.
    public static func spotMark(at time: Double) -> (opacity: Double, scale: Double) {
        let land = EntranceScript.land
        let opacity = time < land ? 0.9 * min(1, time / 0.3) : max(0, 0.9 - (time - land) / 0.12)
        return (opacity, 1 + 0.06 * sin(time * 7))
    }

    /// The landing ring, drawn closed fast then slow, held, then faded out: how much is drawn
    /// and how much shows.
    public static func ring(at time: Double) -> (drawn: Double, opacity: Double) {
        let since = time - EntranceScript.land
        guard since >= 0 else { return (0, 0) }
        let opacity = since < 1.5 ? 1 : max(0, 1 - (since - 1.5) / 0.5)
        return (easeOut(since / 0.42), opacity)
    }

    /// A ring across the floor from the spot on landing, flattened to lie on it: its radius
    /// across, its opacity and its line. Nil before the landing and once it has faded.
    public static func shockwave(at time: Double) -> (radius: Double, opacity: Double, line: Double)? {
        let since = time - EntranceScript.land
        guard since >= 0, since < 0.55 else { return nil }
        let progress = since / 0.55
        return (30 + 95 * easeOut(progress), 0.55 * (1 - progress), 3 * (1 - progress) + 0.5)
    }

    /// How flat the shockwave lies: its height over its width.
    public static let shockwaveFlattening = 0.34

    // MARK: Dust

    /// One puff of dust: where and when it starts, how it drifts, and how it grows.
    public struct Puff: Hashable, Sendable {
        public let start: Double
        public let life: Double
        public let origin: Point
        /// Points per second.
        public let velocity: Point
        public let startRadius: Double
        public let endRadius: Double

        /// Where it is, how big and how strong at a moment; nil when it isn't showing.
        public func state(at time: Double) -> (center: Point, radius: Double, opacity: Double)? {
            let progress = (time - start) / life
            guard progress >= 0, progress <= 1 else { return nil }
            let drift = easeOut(progress)
            let center = Point(
                x: origin.x + velocity.x * life * drift, y: origin.y + velocity.y * life * drift)
            return (center, startRadius + (endRadius - startRadius) * drift, 0.85 * (1 - progress))
        }
    }

    /// Puffs behind the feet while running (to the right, since they run left), a spray ahead
    /// on the skid, and four out to the sides on landing.
    private static func puffs(newcomerX: (Double) -> Double, spot: Point) -> [Puff] {
        let run = EntranceScript.run
        let skid = run + Self.skidInClip
        let floor = spot.y - 3
        var puffs: [Puff] = []
        for index in 0..<6 {
            let start = run + Self.firstStride + Double(index) * 0.13
            puffs.append(
                Puff(
                    start: start, life: 0.45, origin: Point(x: newcomerX(start) + 14, y: floor),
                    velocity: Point(x: 30, y: -14), startRadius: 2.5, endRadius: 7))
        }
        for index in 0..<4 {
            let start = skid + Double(index) * 0.04
            puffs.append(
                Puff(
                    start: start, life: 0.5, origin: Point(x: newcomerX(start) - 10, y: floor),
                    velocity: Point(x: -60 - Double(index) * 22, y: -18 - Double(index) * 4), startRadius: 3,
                    endRadius: 8 + Double(index)))
        }
        for index in 0..<4 {
            let side: Double = index < 2 ? -1 : 1
            puffs.append(
                Puff(
                    start: EntranceScript.land, life: 0.55, origin: Point(x: spot.x, y: floor),
                    velocity: Point(x: side * (70 + Double(index % 2) * 50), y: -10 - Double(index % 2) * 10),
                    startRadius: 3, endRadius: 9))
        }
        return puffs
    }

    /// Into the entrance clip, the first stride on screen, and the skid (heels dig in).
    static let firstStride = 0.4
    static let skidInClip = 1.25

    // MARK: The squad watching

    /// A teammate at `feet` watching the new member run in, from when the squad turns until
    /// `until` (their cheer): eyes and head follow the runner, and the high-energy ones bounce on
    /// their toes. A one-shot clip that ends where it started, so the cheer takes over cleanly.
    /// `facing` is how the teammate is drawn (-1 mirrored), so they still look the right way.
    public func watching(from feet: Point, facing: Double = 1, until: Double, bounces: Bool) throws(AvatarError)
        -> Clip
    {
        let start = EntranceScript.look
        let duration = max(until - start, 0.1)
        let step = 1.0 / 30
        var times: [Double] = []
        var time = 0.0
        while time < duration {
            times.append(time)
            time += step
        }
        times.append(duration)
        // Turning takes a quarter second in, and a tenth back as the cheer starts.
        func weight(_ time: Double) -> Double {
            min(Self.smooth(time / 0.25), Self.smooth((duration - time) / 0.1))
        }
        func across(_ time: Double) -> Double { (newcomerX(at: start + time) - feet.x) * facing }
        let eyes = times.map { Clip.Keyframe(time: $0, value: min(max(across($0) / 9, -7), 7) * weight($0)) }
        let head = times.map { Clip.Keyframe(time: $0, value: min(max(across($0) / 30, -7), 7) * weight($0)) }
        var tracks = [
            Clip.Track(part: "eyes", channel: .x, keys: eyes),
            Clip.Track(part: "head", channel: .rotation, keys: head),
        ]
        if bounces {
            let hop = times.map { time in
                let running = start + time - EntranceScript.run
                return Clip.Keyframe(time: time, value: running > 0 ? -abs(sin(running * 11)) * 7 * weight(time) : 0)
            }
            tracks.append(Clip.Track(part: "root", channel: .y, keys: hop))
        }
        return try Clip(name: "watch", duration: duration, loops: false, tracks: tracks)
    }

    // MARK: Easing

    static func smooth(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    static func easeOut(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}
