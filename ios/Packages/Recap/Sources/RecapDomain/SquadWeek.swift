import Contracts

/// 全队运动总结: every member's week, for the squad's days trained, the sports it trained most
/// and the week's fun numbers (训练最多的一天, 坚持运动最久, 互相加油, 一共练了).
public struct SquadWeek: Hashable, Sendable {
    public struct Member: Hashable, Sendable {
        public let member: MemberID
        /// Monday first.
        public let days: [DayKind]
        /// Monday first, the minutes each trained day logged; nil where none did (minutes are
        /// never asked for), and empty in a week frozen before they were kept.
        public let minutes: [Int?]
        /// Reactions on their posts that week.
        public let reactionsReceived: Int

        public init(member: MemberID, days: [DayKind], minutes: [Int?] = [], reactionsReceived: Int = 0) {
            self.member = member
            self.days = days
            self.minutes = minutes
            self.reactionsReceived = reactionsReceived
        }

        public var trainedDays: Int { days.count { $0.isTrained } }

        /// The sport they trained most days, the earliest on a tie; nil when they didn't train
        /// a listed sport.
        public var topSport: Sport? { SquadWeek.ranked(days).first?.sport }

        /// The minutes logged on a trained day, if any were.
        func minutes(on index: Int) -> Int? {
            guard index < days.count, days[index].isTrained, index < minutes.count else { return nil }
            return minutes[index]
        }
    }

    /// One sport and the days the squad trained it.
    public struct SportDays: Hashable, Sendable {
        public let sport: Sport
        public let days: Int
    }

    /// 训练最多的一天: the day of the week the most members trained.
    public struct BestDay: Hashable, Sendable {
        /// 0 for Monday.
        public let weekday: Int
        public let members: Int
    }

    /// 坚持运动最久: the longest run of days in a row one member trained.
    public struct Streak: Hashable, Sendable {
        public let member: MemberID
        public let days: Int
        /// The run's first day, 0 for Monday.
        public let from: Int

        /// The run's last day, 0 for Monday.
        public var through: Int { from + days - 1 }
    }

    /// 一共练了: the minutes the squad logged, and the day someone trained longest.
    public struct TrainingTime: Hashable, Sendable {
        public let minutes: Int
        public let longest: LongestDay
    }

    /// 请假条: the days the squad took off with one, and who took the most.
    public struct Disclaimers: Hashable, Sendable {
        public let days: Int
        public let most: MemberID
    }

    /// The most minutes one member logged in a day.
    public struct LongestDay: Hashable, Sendable {
        public let member: MemberID
        public let minutes: Int
    }

    /// Everyone in the squad at the awards, in the order they joined.
    public let members: [Member]

    public init(members: [Member]) {
        self.members = members
    }

    /// Days trained by the whole squad: each member's days added up.
    public var trainedDays: Int { members.reduce(0) { $0 + $1.trainedDays } }

    /// Every listed sport the squad trained, most days first; on a tie the one seen first,
    /// member by member in the order they joined.
    public var sports: [SportDays] { Self.ranked(members.flatMap(\.days)) }

    /// The day the most members trained, the earliest on a tie; nil when nobody trained.
    public var bestDay: BestDay? {
        let counts = (0..<7).map { index in
            members.count { index < $0.days.count && $0.days[index].isTrained }
        }
        guard let most = counts.max(), most > 0, let weekday = counts.firstIndex(of: most) else { return nil }
        return BestDay(weekday: weekday, members: most)
    }

    /// The longest run of days in a row anyone trained, the first to join and then the earliest
    /// run on a tie; nil when nobody trained two days in a row, since one day is no streak.
    public var longestStreak: Streak? {
        var best: Streak?
        for member in members {
            var start = 0
            var length = 0
            for (index, day) in member.days.prefix(7).enumerated() {
                if day.isTrained {
                    if length == 0 { start = index }
                    length += 1
                    if length > (best?.days ?? 1) {
                        best = Streak(member: member.member, days: length, from: start)
                    }
                } else {
                    length = 0
                }
            }
        }
        return best
    }

    /// The squad's 请假条 days and who took the most, the first to join on a tie; nil when
    /// nobody took one.
    public var disclaimers: Disclaimers? {
        let counts = members.map { member in member.days.prefix(7).count { $0 == .disclaimer } }
        guard let most = counts.max(), most > 0, let index = counts.firstIndex(of: most) else { return nil }
        return Disclaimers(days: counts.reduce(0, +), most: members[index].member)
    }

    /// 互相加油: every reaction on the squad's posts that week.
    public var reactions: Int { members.reduce(0) { $0 + $1.reactionsReceived } }

    /// The minutes the squad logged and its longest day (the first to join, then the earliest
    /// day, on a tie). Nil unless at least half the days trained logged minutes, since minutes
    /// are never asked for and a total of a few would undersell the week.
    public var time: TrainingTime? {
        var logged = 0
        var total = 0
        var longest: LongestDay?
        for member in members {
            for index in 0..<min(member.days.count, 7) {
                guard let minutes = member.minutes(on: index) else { continue }
                logged += 1
                total += minutes
                if minutes > (longest?.minutes ?? 0) {
                    longest = LongestDay(member: member.member, minutes: minutes)
                }
            }
        }
        guard let longest, logged * 2 >= trainedDays else { return nil }
        return TrainingTime(minutes: total, longest: longest)
    }

    /// Sports ranked by days, the first seen ahead on a tie.
    static func ranked(_ days: [DayKind]) -> [SportDays] {
        var order: [Sport] = []
        var counts: [Sport: Int] = [:]
        for case .trained(let sport?) in days {
            if counts[sport] == nil { order.append(sport) }
            counts[sport, default: 0] += 1
        }
        return order.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (counts[lhs.element] ?? 0, counts[rhs.element] ?? 0)
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map { SportDays(sport: $0.element, days: counts[$0.element] ?? 0) }
    }
}
