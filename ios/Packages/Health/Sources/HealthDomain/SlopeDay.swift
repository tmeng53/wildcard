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

    /// The day from its readings, earliest first; nil without a single run. Heights from GPS
    /// wobble, so the turns are found on smoothed heights and count only past `turnMeters`; a new
    /// run starts only after a climb of `liftMeters` (a lift), so a traverse uphill or wobble
    /// mid-run doesn't split it; a run is a run from `runMeters` down. Speeds are taken five
    /// readings at a time, so up to two bad fixes in a row can't make the top speed, and none past
    /// `speedCeiling` counts.
    public init?(_ samples: [Sample]) {
        let heights = Self.smoothed(samples.map(\.altitude))
        var runs: [Run] = []
        for leg in Self.descents(heights) {
            if let last = runs.last, heights[leg.top] - heights[last.foot] < Self.liftMeters {
                // No lift between them: the same run, from the higher top to the lower foot.
                runs[runs.count - 1] = Run(
                    top: heights[leg.top] > heights[last.top] ? leg.top : last.top,
                    foot: heights[leg.foot] < heights[last.foot] ? leg.foot : last.foot)
            } else {
                runs.append(leg)
            }
        }
        let drop = { (run: Run) in heights[run.top] - heights[run.foot] }
        let counted = runs.filter { drop($0) >= Self.runMeters }
        guard !counted.isEmpty else { return nil }
        self.runs = counted.count
        descentM = counted.map(drop).reduce(0, +).rounded()
        let fastest = counted.compactMap { run in
            Self.steadiest(samples[min(run.top, run.foot)...max(run.top, run.foot)].map(\.speed))
        }.max()
        topSpeedKmh = fastest.map { ($0 * 3.6 * 10).rounded() / 10 }
    }

    /// A rise or fall smaller than this is GPS wobble or a flat, not a turn.
    static let turnMeters = 20.0
    /// The least climb between two runs: a lift, not a traverse.
    static let liftMeters = 50.0
    /// The least drop that counts as a run.
    static let runMeters = 30.0
    /// About 160 km/h: anything faster is a bad fix.
    static let speedCeiling = 45.0

    private struct Run {
        let top: Int
        let foot: Int
    }

    /// Each stretch going down, from a top to the foot after it, found with `turnMeters` of
    /// hysteresis.
    private static func descents(_ heights: [Double]) -> [Run] {
        var legs: [Run] = []
        var (top, low, high) = (0, 0, 0)
        var goingDown = false
        for index in heights.indices {
            if goingDown {
                if heights[index] < heights[low] { low = index }
                if heights[index] - heights[low] >= turnMeters {
                    legs.append(Run(top: top, foot: low))
                    goingDown = false
                    high = index
                }
            } else {
                if heights[index] > heights[high] { high = index }
                if heights[high] - heights[index] >= turnMeters {
                    (top, low) = (high, index)
                    goingDown = true
                }
            }
        }
        if goingDown { legs.append(Run(top: top, foot: low)) }
        return legs
    }

    /// Each height the average of it and its three neighbours on each side.
    private static func smoothed(_ heights: [Double]) -> [Double] {
        heights.indices.map { index in
            let window = heights[max(0, index - 3)...min(heights.count - 1, index + 3)]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// The highest speed held over five readings in a row (the middle of each five once sorted),
    /// leaving out readings with none or past the ceiling.
    private static func steadiest(_ speeds: [Double?]) -> Double? {
        let kept = speeds.compactMap { $0 }.filter { $0 >= 0 && $0 <= speedCeiling }
        guard kept.count >= 5 else { return nil }
        var best = 0.0
        for start in 0...(kept.count - 5) {
            best = max(best, kept[start..<(start + 5)].sorted()[2])
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
