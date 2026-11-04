import Foundation

/// One part's channel values. Unlike a clip, a pose has every channel of every part.
public struct PartPose: Hashable, Sendable {
    public var rotation = 0.0
    // swiftlint:disable:next identifier_name - the channel's name.
    public var x = 0.0
    public var y = 0.0
    public var scaleX = 1.0
    public var scaleY = 1.0
    public var opacity = 1.0
    public var bend = 0.0

    public init(opacity: Double = 1) {
        self.opacity = opacity
    }

    /// Applies an accent's value: offsets add, scales multiply, opacity stays within 0...1.
    mutating func add(_ value: Double, to channel: Channel, strength: Double) {
        switch channel {
        case .rotation, .x, .y, .bend: self[channel] += value * strength
        case .scaleX, .scaleY: self[channel] *= max(0, 1 + (value - 1) * strength)
        case .opacity: opacity = min(max(opacity + value, 0), 1)
        }
    }

    public subscript(channel: Channel) -> Double {
        get {
            switch channel {
            case .rotation: rotation
            case .x: x
            case .y: y
            case .scaleX: scaleX
            case .scaleY: scaleY
            case .opacity: opacity
            case .bend: bend
            }
        }
        set {
            switch channel {
            case .rotation: rotation = newValue
            case .x: x = newValue
            case .y: y = newValue
            case .scaleX: scaleX = newValue
            case .scaleY: scaleY = newValue
            case .opacity: opacity = newValue
            case .bend: bend = newValue
            }
        }
    }
}

/// Every part's channel values, in the figure's part order.
public struct Pose: Hashable, Sendable {
    public var parts: [PartPose]

    public init(parts: [PartPose]) {
        self.parts = parts
    }

    /// Partway from this pose to another: 0 is this one, 1 is `other`. Rotations take the short
    /// way round, so an arm stopped mid-stroke at -500° swings back 140°, not 500°.
    public func blended(to other: Pose, amount: Double) -> Pose {
        Pose(
            parts: zip(parts, other.parts).map { start, target in
                var mixed = start
                for channel in Channel.allCases {
                    var gap = target[channel] - start[channel]
                    if channel == .rotation || channel == .bend { gap = remainder(gap, 360) }
                    mixed[channel] = target[channel] - gap * (1 - amount)
                }
                return mixed
            })
    }
}

/// Where a part is drawn: its art's transform from canvas to canvas, and its opacity
/// including its parents'. A bent arm's art is bent first (`bend`), then transformed.
public struct Placement: Hashable, Sendable {
    public var transform: Transform
    public var opacity: Double
    public var bend: Bend?

    public init(transform: Transform, opacity: Double, bend: Bend? = nil) {
        (self.transform, self.opacity, self.bend) = (transform, opacity, bend)
    }
}
