import Foundation

/// Where a member's four heart-rate zones start, in beats per minute: 轻松, 适中, 剧烈 and 峰值,
/// each higher than the one before. Worked out on the member's own phone from their age and
/// resting heart rate, so a post carries these four numbers and never the age.
public struct HeartRateZones: Hashable, Sendable, Codable {
    public let light: Int
    public let moderate: Int
    public let vigorous: Int
    public let peak: Int

    /// Nil unless each zone starts above the one before, within the API's 20 to 250.
    public init?(light: Int, moderate: Int, vigorous: Int, peak: Int) {
        guard 20 <= light, light < moderate, moderate < vigorous, vigorous < peak, peak <= 250 else { return nil }
        self.light = light
        self.moderate = moderate
        self.vigorous = vigorous
        self.peak = peak
    }

    /// The zones by heart-rate reserve, as Fitbit and the ACSM count them: the highest heart rate
    /// is 208 − 0.7 × age (Tanaka), and each zone starts at a share of the way from the resting
    /// heart rate to it. Without a resting heart rate, shares of the highest heart rate instead.
    /// Nil for an age outside 13 to 100 or a resting rate outside 30 to 120.
    public init?(age: Int, restingBpm: Int?) {
        guard (13...100).contains(age) else { return nil }
        let highest = 208 - 0.7 * Double(age)
        let start: (Double) -> Int
        let shares: [Double]
        if let restingBpm {
            guard (30...120).contains(restingBpm) else { return nil }
            let resting = Double(restingBpm)
            start = { share in Int((resting + share * (highest - resting)).rounded()) }
            shares = Self.reserveShares
        } else {
            start = { share in Int((share * highest).rounded()) }
            shares = Self.highestShares
        }
        self.init(
            light: start(shares[0]), moderate: start(shares[1]), vigorous: start(shares[2]), peak: start(shares[3]))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let zones = Self(
                light: try container.decode(Int.self, forKey: .light),
                moderate: try container.decode(Int.self, forKey: .moderate),
                vigorous: try container.decode(Int.self, forKey: .vigorous),
                peak: try container.decode(Int.self, forKey: .peak))
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .peak, in: container, debugDescription: "Zones must rise from 20 to 250.")
        }
        self = zones
    }

    private enum CodingKeys: String, CodingKey {
        case light, moderate, vigorous, peak
    }

    /// Each zone's start, 轻松 first.
    public var starts: [Int] { [light, moderate, vigorous, peak] }

    /// The zone `bpm` is in; nil below 轻松.
    public func zone(of bpm: Int) -> HeartRateZone? {
        HeartRateZone.allCases.last { starts[$0.rawValue] <= bpm }
    }

    /// Where zone `zone` starts.
    public func start(of zone: HeartRateZone) -> Int { starts[zone.rawValue] }

    /// Seconds spent in each zone over `points`: each reading counts until the next one.
    public func seconds(in points: [HeartRatePoint]) -> [HeartRateZone: Double] {
        var spent: [HeartRateZone: Double] = [:]
        for (point, next) in zip(points, points.dropFirst()) {
            guard let zone = zone(of: point.bpm) else { continue }
            spent[zone, default: 0] += max(0, next.seconds - point.seconds)
        }
        return spent
    }

    /// Shares of the heart-rate reserve where 轻松, 适中, 剧烈 and 峰值 start.
    static let reserveShares = [0.3, 0.4, 0.6, 0.85]
    /// Shares of the highest heart rate, when the resting one isn't known.
    static let highestShares = [0.57, 0.64, 0.77, 0.9]
}

/// One of the four heart-rate zones, the lowest first.
public enum HeartRateZone: Int, CaseIterable, Hashable, Sendable, Comparable {
    case light, moderate, vigorous, peak

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
