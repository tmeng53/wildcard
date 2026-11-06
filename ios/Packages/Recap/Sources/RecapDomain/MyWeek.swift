import Contracts

/// 你的一周: the reader's own week, Monday first.
public struct MyWeek: Hashable, Sendable {
    public let plan: Int
    public let days: [Day]
    public let line: String?
    public let healthyMeals: Int
    public let cheatMeals: Int
    public let reactionsReceived: Int

    public struct Day: Hashable, Sendable {
        public let day: LocalDay
        public let kind: DayKind
        /// The minutes logged that day when it was trained, if any were (they are never asked for).
        public let minutes: Int?

        public init(day: LocalDay, kind: DayKind, minutes: Int? = nil) {
            self.day = day
            self.kind = kind
            self.minutes = kind.isTrained ? minutes : nil
        }
    }

    /// 坚持运动最久: days in a row trained.
    public struct Streak: Hashable, Sendable {
        public let days: Int
        /// The run's first day, 0 for Monday.
        public let from: Int

        /// The run's last day, 0 for Monday.
        public var through: Int { from + days - 1 }
    }

    /// 一共训练了: the minutes logged, and the day logged the most.
    public struct TrainingTime: Hashable, Sendable {
        public let minutes: Int
        /// The longest day, 0 for Monday.
        public let longestDay: Int
        public let longestMinutes: Int
    }

    public init(
        plan: Int, days: [Day], line: String? = nil, healthyMeals: Int, cheatMeals: Int, reactionsReceived: Int
    ) {
        self.plan = plan
        self.days = days
        self.line = line
        self.healthyMeals = healthyMeals
        self.cheatMeals = cheatMeals
        self.reactionsReceived = reactionsReceived
    }

    /// Days trained: the big number.
    public var trainedDays: Int { days.count { $0.kind.isTrained } }

    /// The sport they trained most days, the earliest on a tie; nil when they didn't train a
    /// listed sport.
    public var topSport: Sport? { SquadWeek.ranked(days.map(\.kind)).first?.sport }

    /// The sport they trained most days and its days, the earliest on a tie.
    public var topSportDays: SquadWeek.SportDays? { SquadWeek.ranked(days.map(\.kind)).first }

    /// The longest run of days in a row they trained, the earliest on a tie; nil under two days,
    /// since one day is no streak.
    public var longestStreak: Streak? {
        guard let run = SquadWeek.longestRun(days.map(\.kind)), run.days > 1 else { return nil }
        return Streak(days: run.days, from: run.from)
    }

    /// The minutes they logged and their longest day (the earliest on a tie). Nil unless at least
    /// half the days trained logged minutes, as for the squad.
    public var time: TrainingTime? {
        let logged = days.prefix(7).enumerated().compactMap { index, day in day.minutes.map { (index, $0) } }
        guard let longest = logged.max(by: { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 > $1.0) }),
            logged.count * 2 >= trainedDays
        else { return nil }
        return TrainingTime(
            minutes: logged.reduce(0) { $0 + $1.1 }, longestDay: longest.0, longestMinutes: longest.1)
    }

    /// Which day the character stands over, Monday 0: the last day of their top sport, else the
    /// last day they trained, else midweek.
    public var standsOn: Int {
        let kinds = days.map(\.kind)
        if let sport = topSport, let last = kinds.lastIndex(of: .trained(sport)) { return last }
        return kinds.lastIndex { $0.isTrained } ?? 3
    }
}
