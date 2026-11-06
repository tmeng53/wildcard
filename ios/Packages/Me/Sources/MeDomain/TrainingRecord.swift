import Contracts

/// 训练记录 on 我: the member's last weeks of training as a heatmap, a column a week (Monday on
/// top) and the newest week last, each day as dark as it was trained.
public struct TrainingRecord: Hashable, Sendable {
    /// How hard a day was trained, by its minutes: four shades of ink.
    public enum Level: Int, Hashable, Sendable, Comparable {
        /// No 练了.
        case none = 0
        /// Under half an hour.
        case light
        /// Half an hour to an hour, or a 练了 without minutes.
        case steady
        /// An hour or more, or more than one 练了.
        case hard

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        /// A day's level from its 练了.
        init(_ trainings: [TrainingDay]) {
            switch trainings.count {
            case 0: self = .none
            case 1:
                guard let minutes = trainings[0].minutes else {
                    self = .steady
                    return
                }
                self = minutes >= 60 ? .hard : minutes >= 30 ? .steady : .light
            default: self = .hard
            }
        }
    }

    /// One day on the record.
    public struct Day: Hashable, Sendable, Identifiable {
        public var day: LocalDay
        public var level: Level
        /// The day's 练了, the earliest made first; empty on a day without one.
        public var trainings: [TrainingDay]
        /// A day after today, drawn as an empty outline.
        public var isAhead: Bool

        public var id: LocalDay { day }

        /// What the day's popover says: the sport trained longest (the first on a tie) and the
        /// day's minutes added up, nil when none said how long.
        public var main: TrainingDay? {
            trainings.enumerated().max { lhs, rhs in
                let (left, right) = (lhs.element.minutes ?? 0, rhs.element.minutes ?? 0)
                return left == right ? lhs.offset > rhs.offset : left < right
            }?.element
        }

        /// The day's minutes added up; nil when no 练了 said how long.
        public var minutes: Int? {
            let said = trainings.compactMap(\.minutes)
            return said.isEmpty ? nil : said.reduce(0, +)
        }

        /// The post a tap on the popover opens: the day's main 练了.
        public var post: CheckInID? { main?.id }
    }

    /// How many weeks the record shows: about five months, which fits a phone's width.
    public static let weeks = 21

    /// Columns, the oldest week first, each Monday to Sunday.
    public var columns: [[Day]]

    /// The weeks ending with `today`'s, with each day's 练了 from `trainings` (any order; days
    /// outside the weeks are left out).
    public init(today: LocalDay, trainings: [TrainingDay], weeks: Int = Self.weeks) {
        let first = today.weekStart.adding(days: -7 * (weeks - 1))
        let byDay = Dictionary(grouping: trainings, by: \.day)
        columns = (0..<weeks).map { week in
            (0..<7).map { weekday in
                let day = first.adding(days: week * 7 + weekday)
                let done = byDay[day] ?? []
                return Day(day: day, level: Level(done), trainings: done, isAhead: day > today)
            }
        }
    }

    /// The first day the record shows, a Monday: what to read from.
    public static func firstDay(today: LocalDay, weeks: Int = Self.weeks) -> LocalDay {
        today.weekStart.adding(days: -7 * (weeks - 1))
    }

    /// The months whose first day falls on the record, with the column it starts in: the
    /// labels under it.
    public var months: [(month: Int, column: Int)] {
        columns.enumerated().compactMap { index, week in
            week.first { $0.day.day == 1 }.map { ($0.day.month, index) }
        }
    }
}
