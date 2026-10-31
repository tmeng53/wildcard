import Contracts

/// My week as the squad card's second page shows it: each day Monday to Sunday, what I trained
/// and what I logged on each day. Counts only, never a body number.
public struct WeekRecord: Hashable, Sendable {
    /// How one day stands: one status a day, 练了 over 请假条 over a planned rest day.
    public enum Day: Hashable, Sendable {
        case trained
        case disclaimer
        case restDay
        /// A training day without a check-in, past or still to come.
        case open
    }

    /// An activity I trained on one day, with its minutes added up; nil when no 练了 of it gave any.
    public struct Session: Hashable, Sendable {
        public let activity: Activity
        public let minutes: Int?
    }

    /// What I logged on one day: what I trained and how many meals.
    public struct DayLog: Hashable, Sendable {
        /// In the order first logged, each activity once.
        public let sessions: [Session]
        public let healthyMeals: Int
        public let cheatMeals: Int
    }

    /// An activity I trained this week, and on how many days.
    public struct Trained: Hashable, Sendable {
        public let activity: Activity
        public let days: Int
    }

    /// Monday first, seven days.
    public let days: [Day]
    /// The sport each day shows, Monday first: what I trained that day, else what the plan names;
    /// nil for a rest day, a 请假条 or a training day with no sport.
    public let activities: [Activity?]
    /// Today's index in `days`.
    public let today: Int
    /// Most days first; ties in the order first trained.
    public let trained: [Trained]
    /// Monday first, seven days.
    public let logs: [DayLog]
}

extension Home {
    /// My week around `day`, from my check-ins the home holds and my plan.
    public func week(on day: LocalDay) -> WeekRecord {
        let monday = day.weekStart
        let mine = checkIns.filter { $0.member == member && $0.day.weekStart == monday }
        let days = (0..<7).map { offset -> WeekRecord.Day in
            let date = monday.adding(days: offset)
            let entries = mine.filter { $0.day == date }.map(\.entry)
            if entries.contains(where: { if case .trained = $0 { true } else { false } }) { return .trained }
            if entries.contains(where: { if case .disclaimer = $0 { true } else { false } }) { return .disclaimer }
            return isRestDay(date) ? .restDay : .open
        }

        let activities = (0..<7).map { shownActivity(on: monday.adding(days: $0), mine: mine) }

        // Several of the same activity on one day count as one day of it.
        var trainedActivities: [Activity] = []
        var daysOf: [Activity: Set<LocalDay>] = [:]
        for checkIn in mine {
            guard case .trained(let training) = checkIn.entry else { continue }
            if daysOf[training.activity] == nil { trainedActivities.append(training.activity) }
            daysOf[training.activity, default: []].insert(checkIn.day)
        }
        let trained = trainedActivities.enumerated()
            .map {
                (order: $0.offset, item: WeekRecord.Trained(activity: $0.element, days: daysOf[$0.element]?.count ?? 0))
            }
            .sorted { ($1.item.days, $0.order) < ($0.item.days, $1.order) }
            .map(\.item)

        return WeekRecord(
            days: days, activities: activities, today: day.weekday - 1, trained: trained,
            logs: (0..<7).map { offset in Self.log(of: mine.filter { $0.day == monday.adding(days: offset) }) })
    }

    /// One day's log from that day's check-ins, oldest first.
    private static func log(of checkIns: [CheckIn]) -> WeekRecord.DayLog {
        var order: [Activity] = []
        var minutes: [Activity: Int] = [:]
        for checkIn in checkIns.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard case .trained(let training) = checkIn.entry else { continue }
            if !order.contains(training.activity) { order.append(training.activity) }
            if let added = training.minutes?.value { minutes[training.activity, default: 0] += added }
        }
        return WeekRecord.DayLog(
            sessions: order.map { WeekRecord.Session(activity: $0, minutes: minutes[$0]) },
            healthyMeals: checkIns.count { if case .healthyMeal = $0.entry { true } else { false } },
            cheatMeals: checkIns.count { if case .cheatMeal = $0.entry { true } else { false } })
    }

    /// What `date` shows: the sport I trained on it, else the one the plan names.
    private func shownActivity(on date: LocalDay, mine: [CheckIn]) -> Activity? {
        for checkIn in mine where checkIn.day == date {
            if case .trained(let training) = checkIn.entry { return training.activity }
        }
        let offset = date.weekday - 1
        guard date.weekStart == plan.weekStart, plan.days.indices.contains(offset),
            case .train(let planned?) = plan.days[offset]
        else { return nil }
        return planned
    }
}
