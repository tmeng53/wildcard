import Contracts

/// A heart-rate curve as its chart reads it: the stretches of the line each in one zone, where a
/// finger on it lands, the range the axis covers and the minutes spent in each zone. Without
/// zones the whole curve is one stretch with no zone.
public struct HeartRateTrace: Equatable, Sendable {
    /// A run of readings in the same zone (nil below 轻松 or without zones). Each stretch starts
    /// with the last reading of the one before, so the line has no gaps.
    public struct Stretch: Equatable, Sendable {
        public let zone: HeartRateZone?
        public let points: [HeartRatePoint]
    }

    public let points: [HeartRatePoint]
    public let zones: HeartRateZones?

    public init(points: [HeartRatePoint], zones: HeartRateZones?) {
        self.points = points
        self.zones = zones
    }

    public var stretches: [Stretch] {
        guard let first = points.first else { return [] }
        var stretches: [Stretch] = []
        var zone = zones?.zone(of: first.bpm)
        var run = [first]
        for point in points.dropFirst() {
            let next = zones?.zone(of: point.bpm)
            if next != zone {
                stretches.append(Stretch(zone: zone, points: run))
                run = [run[run.count - 1]]
                zone = next
            }
            run.append(point)
        }
        stretches.append(Stretch(zone: zone, points: run))
        return stretches
    }

    /// The reading closest in time to `seconds` from the start.
    public func reading(at seconds: Double) -> HeartRatePoint? {
        points.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) }
    }

    /// The beats per minute the axis covers: every reading and every zone's start, with a margin.
    public var bpmRange: ClosedRange<Int> {
        let readings = points.map(\.bpm)
        let lowest = min(readings.min() ?? 60, zones?.light ?? Int.max)
        let highest = max(readings.max() ?? 180, zones?.peak ?? Int.min)
        return (lowest - Self.margin)...(highest + Self.margin)
    }

    /// Whole minutes in each zone, every zone listed, 轻松 first; empty without zones.
    public var minutes: [(zone: HeartRateZone, minutes: Int)] {
        guard let zones else { return [] }
        let spent = zones.seconds(in: points)
        return HeartRateZone.allCases.map { ($0, Int(((spent[$0] ?? 0) / 60).rounded())) }
    }

    static let margin = 6
}
