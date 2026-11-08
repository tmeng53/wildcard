import Contracts

/// A ski or snowboard day's 趟数 · 落差 · 最高速, worked out on the phone from the workout's route,
/// as Slopes does, so no tracking of our own (Tracy, 2026-11-08). The route keeps only latitude and
/// longitude once posted; these three numbers are all of the height and speed that leave the
/// phone, and never reach AI.
public struct SlopeDay: Hashable, Sendable {
    /// Runs down, each from a lift's top to the foot of the slope; the ride up is no run.
    public let runs: Int
    /// Metres skied down, every run's drop added up.
    public let descentM: Double
    /// The fastest moment on a run, km/h; nil when the route has no speeds.
    public let topSpeedKmh: Double?

    /// One reading of the route: when, how high and how fast.
    public struct Sample: Hashable, Sendable {
        /// Seconds from the workout's start.
        public let seconds: Double
        /// Metres above sea level.
        public let altitude: Double
        /// Metres a second; nil where the phone or watch had none.
        public let speed: Double?

        public init(seconds: Double, altitude: Double, speed: Double?) {
            self.seconds = seconds
            self.altitude = altitude
            self.speed = speed
        }
    }

    /// The day from its readings, earliest first; nil without a single run. GPS height wobbles by
    /// a few metres, so the turns are found on smoothed heights, a turn counts only past `turnMeters`, and a run
    /// only from `runMeters` down; speeds are taken three readings at a time, so one bad fix can't
    /// make the top speed, and none past `speedCeiling` counts.
    public init?(_ samples: [Sample]) {
        let heights = Self.smoothed(samples.map(\.altitude))
        var runs: [(top: Int, foot: Int)] = []
        var top = 0
        var low = 0
        var high = 0
        var goingDown = false
        for index in heights.indices {
            if goingDown {
                if heights[index] < heights[low] { low = index }
                if heights[index] - heights[low] >= Self.turnMeters {
                    runs.append((top, low))
                    goingDown = false
                    high = index
                }
            } else {
                if heights[index] > heights[high] { high = index }
                if heights[high] - heights[index] >= Self.turnMeters {
                    top = high
                    low = index
                    goingDown = true
                }
            }
        }
        if goingDown { runs.append((top, low)) }
        // The turns are found on the smoothed heights, and each run measured on the readings
        // there, which smoothing would cut short at a sharp top or foot.
        let drop = { (run: (top: Int, foot: Int)) in samples[run.top].altitude - samples[run.foot].altitude }
        let counted = runs.filter { drop($0) >= Self.runMeters }
        guard !counted.isEmpty else { return nil }
        self.runs = counted.count
        descentM = counted.map(drop).reduce(0, +).rounded()
        let fastest = counted.compactMap { run in Self.steadiest(samples[run.top...run.foot].map(\.speed)) }.max()
        topSpeedKmh = fastest.map { ($0 * 3.6 * 10).rounded() / 10 }
    }

    /// A rise or fall smaller than this is GPS wobble or a flat, not a turn.
    static let turnMeters = 20.0
    /// The least drop that counts as a run.
    static let runMeters = 30.0
    /// About 160 km/h: anything faster is a bad fix.
    static let speedCeiling = 45.0

    /// Each height the average of it and its two neighbours on each side.
    private static func smoothed(_ heights: [Double]) -> [Double] {
        heights.indices.map { index in
            let window = heights[max(0, index - 2)...min(heights.count - 1, index + 2)]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// The highest speed held over three readings in a row (the middle of each three), leaving
    /// out readings with none or past the ceiling.
    private static func steadiest(_ speeds: [Double?]) -> Double? {
        let kept = speeds.compactMap { $0 }.filter { $0 >= 0 && $0 <= speedCeiling }
        guard kept.count >= 3 else { return nil }
        var best = 0.0
        for middle in 1..<(kept.count - 1) {
            let three = [kept[middle - 1], kept[middle], kept[middle + 1]].sorted()
            best = max(best, three[1])
        }
        return best
    }
}

extension WorkoutSummary {
    /// With a ski day's 趟数 · 落差 · 最高速, which take the place of its heart rate on the 成绩条
    /// (its chart still shows it).
    public func skied(_ day: SlopeDay) -> WorkoutSummary {
        var skied = self
        skied.runs = day.runs
        skied.descentM = day.descentM
        skied.topSpeedKmh = day.topSpeedKmh
        skied.avgHr = nil
        skied.maxHr = nil
        skied.effort = nil
        return skied
    }
}
