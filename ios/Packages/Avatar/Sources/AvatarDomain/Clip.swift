import Foundation

/// What a track moves. Rotation is in degrees, clockwise; x and y are in canvas points,
/// added to the rest pose; scales and opacity are factors.
public enum Channel: String, Hashable, Sendable, Codable, CaseIterable {
    // swiftlint:disable:next identifier_name - x and y are the clip files' own channel names.
    case rotation, x, y, scaleX, scaleY, opacity
}

/// How a value travels from the previous key to this one.
public enum Easing: Hashable, Sendable {
    case linear
    /// Stays at the previous key's value, then jumps.
    case hold
    /// A CSS-style `cubic-bezier(x1, y1, x2, y2)` timing curve.
    case cubicBezier(Double, Double, Double, Double)

    public static let easeIn = Easing.cubicBezier(0.42, 0, 1, 1)
    public static let easeOut = Easing.cubicBezier(0, 0, 0.58, 1)
    public static let easeInOut = Easing.cubicBezier(0.42, 0, 0.58, 1)
    /// Overshoots a little and settles: for landings and pops.
    public static let backOut = Easing.cubicBezier(0.34, 1.56, 0.64, 1)

    static let named: [String: Easing] = [
        "linear": .linear, "hold": .hold, "easeIn": .easeIn, "easeOut": .easeOut, "easeInOut": .easeInOut,
        "backOut": .backOut,
    ]

    /// Progress (0...1, or past it for overshoot) at a fraction of the way through time.
    public func progress(_ fraction: Double) -> Double {
        switch self {
        case .linear: fraction
        case .hold: fraction >= 1 ? 1 : 0
        case .cubicBezier(let firstX, let firstY, let secondX, let secondY):
            Self.bezier(x: (firstX, secondX), y: (firstY, secondY), at: fraction)
        }
    }

    /// Finds the curve parameter whose x is `fraction`, then returns its y. Newton's method,
    /// with bisection when the slope is too flat, as browsers do. The curve runs from (0, 0)
    /// to (1, 1) with its two control points' x and y given as pairs.
    private static func bezier(
        x controlX: (Double, Double), y controlY: (Double, Double), at fraction: Double
    ) -> Double {
        if fraction <= 0 { return 0 }
        if fraction >= 1 { return 1 }
        func coordinate(_ parameter: Double, _ control: (Double, Double)) -> Double {
            let (first, second) = control
            return ((1 + 3 * first - 3 * second) * parameter + (3 * second - 6 * first)) * parameter * parameter
                + 3 * first * parameter
        }
        func slope(_ parameter: Double) -> Double {
            let (first, second) = controlX
            return 3 * (1 + 3 * first - 3 * second) * parameter * parameter + 2 * (3 * second - 6 * first) * parameter
                + 3 * first
        }
        var parameter = fraction
        for _ in 0..<8 {
            let error = coordinate(parameter, controlX) - fraction
            if abs(error) < 1e-7 { return coordinate(parameter, controlY) }
            let gradient = slope(parameter)
            if abs(gradient) < 1e-6 { break }
            parameter -= error / gradient
        }
        var (low, high) = (0.0, 1.0)
        parameter = fraction
        for _ in 0..<40 {
            let value = coordinate(parameter, controlX)
            if abs(value - fraction) < 1e-7 { break }
            if value < fraction { low = parameter } else { high = parameter }
            parameter = (low + high) / 2
        }
        return coordinate(parameter, controlY)
    }
}

/// A named move, such as `idle` or `cheer`: keyframed tracks over a duration. Read from
/// a clip's JSON file. Clips name parts but don't know the rig until a `Figure` binds them.
public struct Clip: Hashable, Sendable {
    /// The only `version` of clip JSON this build reads.
    public static let currentVersion = 1

    public var name: String
    /// Seconds.
    public var duration: Double
    /// Loops forever (idle) or plays once and hands back to the idle clip (cheer).
    public var loops: Bool
    public var tracks: [Track]

    public struct Track: Hashable, Sendable {
        public var part: PartID
        public var channel: Channel
        /// In time order.
        public var keys: [Keyframe]

        public init(part: PartID, channel: Channel, keys: [Keyframe]) {
            (self.part, self.channel, self.keys) = (part, channel, keys)
        }

        /// The value at a time in the clip. Before the first key it is the first key's
        /// value, after the last the last's.
        public func value(at time: Double) -> Double {
            guard let first = keys.first, let last = keys.last else { return 0 }
            if time <= first.time { return first.value }
            if time >= last.time { return last.value }
            // Few keys per track, so a scan beats a binary search.
            for index in 1..<keys.count where time < keys[index].time {
                let (previous, next) = (keys[index - 1], keys[index])
                let fraction = (time - previous.time) / (next.time - previous.time)
                return previous.value + (next.value - previous.value) * next.easing.progress(fraction)
            }
            return last.value
        }
    }

    public struct Keyframe: Hashable, Sendable {
        /// Seconds from the start of the clip.
        public var time: Double
        public var value: Double
        /// How the value travels here from the previous key.
        public var easing: Easing

        public init(time: Double, value: Double, easing: Easing = .linear) {
            (self.time, self.value, self.easing) = (time, value, easing)
        }
    }

    public init(name: String, duration: Double, loops: Bool, tracks: [Track]) throws(AvatarError) {
        guard duration > 0, duration.isFinite else { throw .invalidDuration(clip: name) }
        for track in tracks {
            let times = track.keys.map(\.time)
            let ordered = zip(times, times.dropFirst()).allSatisfy { $0 < $1 }
            guard let first = times.first, let last = times.last, ordered, first >= 0, last <= duration else {
                throw .invalidKeyframes(clip: name, part: track.part, channel: track.channel)
            }
        }
        (self.name, self.duration, self.loops, self.tracks) = (name, duration, loops, tracks)
    }

    public static func decode(_ data: Data) throws(AvatarError) -> Clip {
        let file: ClipFile = try decodeJSON(data, version: currentVersion)
        var tracks: [Track] = []
        for track in file.tracks {
            var keys: [Keyframe] = []
            for key in track.keys {
                keys.append(Keyframe(time: key.time, value: key.value, easing: try easing(key.ease, file.name)))
            }
            tracks.append(Track(part: track.part, channel: track.channel, keys: keys))
        }
        return try Clip(name: file.name, duration: file.duration, loops: file.loops, tracks: tracks)
    }

    private static func easing(_ given: EaseFile?, _ clip: String) throws(AvatarError) -> Easing {
        switch given {
        case nil: return .linear
        case .name(let name)?:
            guard let easing = Easing.named[name] else { throw .malformedJSON("\(clip): unknown ease \"\(name)\"") }
            return easing
        case .bezier(let numbers)?: return .cubicBezier(numbers[0], numbers[1], numbers[2], numbers[3])
        }
    }
}

private struct ClipFile: Decodable {
    let name: String
    let duration: Double
    let loops: Bool
    let tracks: [TrackFile]

    struct TrackFile: Decodable {
        let part: PartID
        let channel: Channel
        let keys: [KeyFrameFile]
    }
}

private struct KeyFrameFile: Decodable {
    let time: Double
    let value: Double
    let ease: EaseFile?

    enum CodingKeys: String, CodingKey {
        case time = "t", value = "v", ease
    }
}

/// `"easeOut"`, or the four numbers of a cubic Bézier.
private enum EaseFile: Decodable {
    case name(String)
    /// Exactly four numbers.
    case bezier([Double])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            self = .name(name)
            return
        }
        let numbers = try container.decode([Double].self)
        guard numbers.count == 4 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "a cubic Bézier has 4 numbers")
        }
        self = .bezier(numbers)
    }
}
