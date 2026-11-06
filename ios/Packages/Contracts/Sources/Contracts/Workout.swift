import Foundation

/// The workout a 训练 was posted from, such as an Apple Health workout: who recorded it, when,
/// the numbers the member kept, and the data its map or chart tile draws. Provider-neutral:
/// every number is optional, one adapter per provider fills what it has, and every screen shows
/// only what is there. Only what the member posts leaves the phone; heart rate never goes to AI.
public struct Workout: Hashable, Sendable, Codable {
    /// Where it was recorded, and the provider's own id, which a member posts once.
    public let source: WorkoutSource
    public let startedAt: Timestamp
    public let endedAt: Timestamp
    public let summary: WorkoutSummary
    /// What the chart tile draws; nil without one.
    public let series: WorkoutSeries?
    /// The route the map tile draws, start first, with `trimMeters` cut from each end; nil
    /// without one.
    public let route: [RoutePoint]?
    /// Where the map or chart tile sits among the photos, 1 being the cover; nil when there is no
    /// tile. A tile is there exactly when a route or a series is.
    public let tilePosition: Int?

    /// How much of the route is cut from each end on the phone, so a home address doesn't show.
    public static let trimMeters = 200.0
    /// The most route points kept; the API's limit.
    public static let routePointsMax = 2000
    /// About how many heart-rate points the chart keeps.
    public static let heartRatePoints = 120

    public init(
        source: WorkoutSource, startedAt: Timestamp, endedAt: Timestamp, summary: WorkoutSummary,
        series: WorkoutSeries? = nil, route: [RoutePoint]? = nil, tilePosition: Int? = nil
    ) {
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.series = series
        self.route = route
        self.tilePosition = tilePosition
    }

    /// The tile it would add to a post: the map with a route, else the chart with a series.
    public var tile: WorkoutTile? {
        if let route, route.count >= 2 { return .map }
        if series?.isDrawable == true { return .chart }
        return nil
    }

    /// The 成绩条 cell the chart shows over time: 趟数 for a lap chart, 平均心率 for a heart-rate
    /// one; nil without a chart. Striking it takes the chart off too.
    public var chartCell: WorkoutCell? {
        guard tile == .chart else { return nil }
        return series?.laps?.isEmpty == false ? .laps : .averageHeartRate
    }

    /// As posted: the numbers not `struck`, and the tile's data only where the tile is kept,
    /// at `tilePosition`, and its chart not struck through `chartCell`.
    public func posting(struck: Set<WorkoutCell>, tilePosition: Int?) -> Workout {
        let chartStruck = chartCell.map(struck.contains) ?? false
        let keepsTile = tilePosition != nil && tile != nil && !chartStruck
        return Workout(
            source: source, startedAt: startedAt, endedAt: endedAt, summary: summary.without(struck),
            series: keepsTile && tile == .chart ? series : nil,
            route: keepsTile && tile == .map ? route : nil,
            tilePosition: keepsTile ? tilePosition : nil)
    }
}

/// Who recorded a workout, and their id for it.
public struct WorkoutSource: Hashable, Sendable, Codable {
    /// `apple_health`; later `fitbit`, `garmin`.
    public let provider: String
    public let id: String

    public static let appleHealth = "apple_health"

    public init(provider: String, id: String) {
        self.provider = provider
        self.id = id
    }
}

/// The tile a workout adds to a post's photos.
public enum WorkoutTile: Hashable, Sendable {
    /// The route on a map.
    case map
    /// Heart rate over the workout, or each lap's time for a swim.
    case chart
}

/// A workout's numbers, as the provider gave them: never converted into other units.
public struct WorkoutSummary: Hashable, Sendable, Codable {
    public var durationSec: Int?
    public var distanceM: Double?
    /// Seconds per kilometre, for a run or walk.
    public var paceSecPerKm: Double?
    /// Kilometres an hour, for a ride.
    public var speedKmh: Double?
    public var avgHr: Int?
    public var maxHr: Int?
    /// How hard it felt, 1 to 10.
    public var effort: Double?
    /// Lengths of the pool, for a swim with its pool length set.
    public var laps: Int?
    public var poolLengthM: Double?

    public init(
        durationSec: Int? = nil, distanceM: Double? = nil, paceSecPerKm: Double? = nil, speedKmh: Double? = nil,
        avgHr: Int? = nil, maxHr: Int? = nil, effort: Double? = nil, laps: Int? = nil, poolLengthM: Double? = nil
    ) {
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.paceSecPerKm = paceSecPerKm
        self.speedKmh = speedKmh
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.effort = effort
        self.laps = laps
        self.poolLengthM = poolLengthM
    }

    /// Its cells on a 成绩条, in order: 时长 first, then each number it has.
    public var cells: [WorkoutCell] {
        WorkoutCell.allCases.filter { has($0) }
    }

    public func has(_ cell: WorkoutCell) -> Bool {
        switch cell {
        case .duration: durationSec != nil
        case .laps: laps != nil
        case .distance: distanceM != nil
        case .pace: paceSecPerKm != nil
        case .speed: speedKmh != nil
        case .averageHeartRate: avgHr != nil
        case .maxHeartRate: maxHr != nil
        case .effort: effort != nil
        }
    }

    /// Without the `struck` cells. 时长 always stays. Laps take the pool length with them.
    public func without(_ struck: Set<WorkoutCell>) -> WorkoutSummary {
        var kept = self
        for cell in struck {
            switch cell {
            case .duration: break
            case .laps:
                kept.laps = nil
                kept.poolLengthM = nil
            case .distance: kept.distanceM = nil
            case .pace: kept.paceSecPerKm = nil
            case .speed: kept.speedKmh = nil
            case .averageHeartRate: kept.avgHr = nil
            case .maxHeartRate: kept.maxHr = nil
            case .effort: kept.effort = nil
            }
        }
        return kept
    }
}

/// One cell of a 成绩条, in the order the strip shows them.
public enum WorkoutCell: String, CaseIterable, Hashable, Sendable, Codable {
    case duration, laps, distance, pace, speed, averageHeartRate, maxHeartRate, effort
}

/// What a workout's chart draws.
public struct WorkoutSeries: Hashable, Sendable, Codable {
    /// Heart rate over the workout, earliest first.
    public let heartRate: [HeartRatePoint]?
    /// Each lap's time in seconds, in order, for a swim.
    public let laps: [Double]?

    public init(heartRate: [HeartRatePoint]? = nil, laps: [Double]? = nil) {
        self.heartRate = heartRate
        self.laps = laps
    }

    private enum CodingKeys: String, CodingKey {
        case heartRate = "hr"
        case laps
    }

    /// Laps make the chart when there are any; else heart rate, with two points at least.
    public var isDrawable: Bool {
        if let laps, !laps.isEmpty { return true }
        return (heartRate?.count ?? 0) >= 2
    }

    /// The fastest lap's index, which the chart draws in white.
    public var fastestLap: Int? {
        guard let laps else { return nil }
        return laps.indices.min { laps[$0] < laps[$1] }
    }
}

/// Heart rate at a moment, seconds from the start.
public struct HeartRatePoint: Hashable, Sendable, Codable {
    /// Seconds from the start.
    public let seconds: Double
    public let bpm: Int

    public init(seconds: Double, bpm: Int) {
        self.seconds = seconds
        self.bpm = bpm
    }

    private enum CodingKeys: String, CodingKey {
        case seconds = "t"
        case bpm
    }
}

/// A point on a route.
public struct RoutePoint: Hashable, Sendable, Codable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

extension [RoutePoint] {
    /// The route without its first and last `meters` along the way, so where it starts and ends
    /// (often home) doesn't show. Empty when the route is no longer than twice that.
    public func trimmed(meters: Double = Workout.trimMeters) -> [RoutePoint] {
        guard count >= 2 else { return [] }
        var along = [0.0]
        for index in 1..<count { along.append(along[index - 1] + self[index - 1].meters(to: self[index])) }
        guard let total = along.last, total > 2 * meters else { return [] }
        return indices.filter { along[$0] >= meters && along[$0] <= total - meters }.map { self[$0] }
    }

    /// At most `limit` points, spread evenly along the list, the first and last kept.
    public func thinned(to limit: Int = Workout.routePointsMax) -> [RoutePoint] {
        Array(evenly(self, limit: limit))
    }
}

extension [HeartRatePoint] {
    /// At most `limit` points, each the average of its stretch, so the curve keeps its shape.
    public func thinned(to limit: Int = Workout.heartRatePoints) -> [HeartRatePoint] {
        guard count > limit, limit >= 2 else { return self }
        let stretch = Double(count) / Double(limit)
        return (0..<limit).map { slot in
            let start = Int(Double(slot) * stretch)
            let end = Swift.min(count, Swift.max(start + 1, Int(Double(slot + 1) * stretch)))
            let part = self[start..<end]
            let bpm = Double(part.map(\.bpm).reduce(0, +)) / Double(part.count)
            return HeartRatePoint(seconds: part[part.startIndex].seconds, bpm: Int(bpm.rounded()))
        }
    }
}

/// Up to `limit` of `items`, evenly spaced, the first and last always among them.
private func evenly<T>(_ items: [T], limit: Int) -> [T] {
    guard items.count > limit, limit >= 2 else { return items }
    let step = Double(items.count - 1) / Double(limit - 1)
    return (0..<limit).map { items[Int((Double($0) * step).rounded())] }
}

extension RoutePoint {
    /// The distance to `other` along the ground, in metres (haversine).
    public func meters(to other: RoutePoint) -> Double {
        let earth = 6_371_000.0
        let lat1 = lat * .pi / 180
        let lat2 = other.lat * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.lon - lon) * .pi / 180
        let chord = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earth * atan2(chord.squareRoot(), (1 - chord).squareRoot())
    }
}

/// One page of a post's cover: a photo, or the workout's map or chart.
public enum PostTile: Hashable, Sendable {
    case photo(PhotoRef)
    case workout(WorkoutTile)
}

extension Training {
    /// The cover's pages in the member's order: the photos, with the workout's tile at its place
    /// among them (1 is the cover). Empty without photos or a tile.
    public var tiles: [PostTile] {
        var tiles = (photos?.all ?? []).map(PostTile.photo)
        if let workout, let tile = workout.tile, let position = workout.tilePosition {
            tiles.insert(.workout(tile), at: min(max(position - 1, 0), tiles.count))
        }
        return tiles
    }
}
