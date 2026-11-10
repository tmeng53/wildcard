import Contracts

/// 外卡记录: the member's records since they joined, as the API works them out on each read, and
/// how they stand in their squad. Opened from 训练记录's 全部数据 on 我.
public struct WildcardRecords: Hashable, Sendable {
    /// A run of days in a row.
    public struct Streak: Hashable, Sendable {
        public var days: Int
        public var first: LocalDay
        public var last: LocalDay

        public init(days: Int, first: LocalDay, last: LocalDay) {
            (self.days, self.first, self.last) = (days, first, last)
        }
    }

    /// A sport and on how many days the member trained it.
    public struct SportDays: Hashable, Sendable {
        public var activity: Activity
        public var days: Int

        public init(activity: Activity, days: Int) {
            (self.activity, self.days) = (activity, days)
        }
    }

    /// Days with a 练了.
    public var trainedDays: Int
    /// Minutes of every 练了 that says how long it took.
    public var minutes: Int
    /// The longest single 练了, when one says how long.
    public var longestMinutes: Int?
    /// Most days trained in a row; a planned rest day between them neither breaks nor adds.
    public var longestStreak: Streak?
    /// Most days in a row with a 健康餐.
    public var mealStreak: Streak?
    /// The days trained in a row still going; nil once broken. Today not trained yet doesn't
    /// break it.
    public var currentStreak: Streak?
    /// The days in a row with a 健康餐 still going; nil once broken.
    public var currentMealStreak: Streak?
    /// 练了 by the hour of the member's clock they were posted at, 0 to 23; 补打卡 left out.
    public var hours: [Int]
    /// Days trained by weekday, Monday first.
    public var weekdays: [Int]
    /// The sports trained on the most days, most first, at most three.
    public var sports: [SportDays]
    /// How many different sports the member trained.
    public var sportCount: Int
    /// How the member stands in their squad; nil outside one.
    public var squad: SquadStanding?

    public init(
        trainedDays: Int, minutes: Int, longestMinutes: Int?, longestStreak: Streak?, mealStreak: Streak?,
        currentStreak: Streak? = nil, currentMealStreak: Streak? = nil,
        hours: [Int], weekdays: [Int], sports: [SportDays], sportCount: Int, squad: SquadStanding?
    ) {
        (self.trainedDays, self.minutes, self.longestMinutes) = (trainedDays, minutes, longestMinutes)
        (self.longestStreak, self.mealStreak) = (longestStreak, mealStreak)
        (self.currentStreak, self.currentMealStreak) = (currentStreak, currentMealStreak)
        (self.hours, self.weekdays, self.sports, self.sportCount, self.squad) =
            (hours, weekdays, sports, sportCount, squad)
    }

    /// Whether `current`, the run still going, is the record `longest`: the tile then reads
    /// 正在刷新纪录 and its days run 至今.
    public static func breaksRecord(current: Streak?, longest: Streak?) -> Bool {
        guard let current, let longest else { return false }
        return current.days >= longest.days
    }

    /// Before the first 练了 the page shows only the two streak tiles, both at 0.
    public var hasTrained: Bool { trainedDays > 0 }

    /// The hour the member trains at most often, the latest on a tie; nil before one is on the
    /// clock (only 补打卡 so far).
    public var usualHour: Int? {
        var best: Int?
        for (hour, count) in hours.enumerated() where count > 0 && count >= (best.map { hours[$0] } ?? 0) {
            best = hour
        }
        return best
    }

    /// The weekday, 0 for Monday, trained on the most days, the first on a tie; nil before any.
    public var busiestWeekday: Int? {
        guard let most = weekdays.max(), most > 0 else { return nil }
        return weekdays.firstIndex(of: most)
    }

    /// Whole hours trained, rounded down (一共 21 小时).
    public var hoursTrained: Int { minutes / 60 }
}

/// A squadmate as 外卡记录 names them: their character, when they made one.
public struct RecordMate: Hashable, Sendable {
    public var member: MemberID
    public var character: MeCharacter?

    public init(member: MemberID, character: MeCharacter?) {
        (self.member, self.character) = (member, character)
    }
}

/// 和小队: the member's best partner, the cheers both ways and what they alone are first at.
public struct SquadStanding: Hashable, Sendable {
    /// A squadmate and a count: shared days, or cheers.
    public struct MateCount: Hashable, Sendable {
        public var mate: RecordMate
        public var count: Int

        public init(mate: RecordMate, count: Int) {
            (self.mate, self.count) = (mate, count)
        }
    }

    /// Reactions, all time, and the squadmate with the most.
    public struct Cheers: Hashable, Sendable {
        public var count: Int
        public var top: MateCount?

        public init(count: Int, top: MateCount?) {
            (self.count, self.top) = (count, top)
        }
    }

    /// What the member alone is first at in the squad; never a tie, never a last place.
    public enum First: String, Hashable, Sendable, CaseIterable {
        case latestTrainer, earliestTrainer, topSport, mostDays
    }

    /// The squadmate who trained on the same days as the member the most.
    public var partner: MateCount?
    public var cheersReceived: Cheers
    public var cheersGiven: Cheers
    /// In the order the API sends them; kinds this build doesn't know are left out.
    public var firsts: [First]

    public init(partner: MateCount?, cheersReceived: Cheers, cheersGiven: Cheers, firsts: [First]) {
        (self.partner, self.cheersReceived, self.cheersGiven, self.firsts) =
            (partner, cheersReceived, cheersGiven, firsts)
    }
}
