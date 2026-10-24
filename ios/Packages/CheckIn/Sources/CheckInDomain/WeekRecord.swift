import Contracts

/// My week as the squad card's second page shows it: each day Monday to Sunday, what I trained
/// and how many meals I logged. Counts only, never a body number.
public struct WeekRecord: Hashable, Sendable {
    /// How one day stands: one status a day, 练了 over 请假条 over a planned rest day.
    public enum Day: Hashable, Sendable {
        case trained
        case disclaimer
        case restDay
        /// A training day without a check-in, past or still to come.
        case open
    }

    /// An activity I trained this week, and on how many days.
    public struct Trained: Hashable, Sendable {
        public let activity: Activity
        public let days: Int
    }

    /// Monday first, seven days.
    public let days: [Day]
    /// The sport planned for each day, Monday first; nil for a rest day or a training day without one.
    public let plannedActivities: [Activity?]
    /// Today's index in `days`.
    public let today: Int
    /// Most days first; ties in the order first trained.
    public let trained: [Trained]
    public let healthyMeals: Int
    public let cheatMeals: Int
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

        let plannedActivities = (0..<7).map { offset -> Activity? in
            let date = monday.adding(days: offset)
            guard date.weekStart == plan.weekStart, plan.days.indices.contains(offset),
                case .train(let planned?) = plan.days[offset]
            else { return nil }
            return planned
        }

        // Several of the same activity on one day count as one day of it.
        var activities: [Activity] = []
        var daysOf: [Activity: Set<LocalDay>] = [:]
        for checkIn in mine {
            guard case .trained(let training) = checkIn.entry else { continue }
            if daysOf[training.activity] == nil { activities.append(training.activity) }
            daysOf[training.activity, default: []].insert(checkIn.day)
        }
        let trained = activities.enumerated()
            .map {
                (order: $0.offset, item: WeekRecord.Trained(activity: $0.element, days: daysOf[$0.element]?.count ?? 0))
            }
            .sorted { ($1.item.days, $0.order) < ($0.item.days, $1.order) }
            .map(\.item)

        return WeekRecord(
            days: days, plannedActivities: plannedActivities, today: day.weekday - 1, trained: trained,
            healthyMeals: mine.count { if case .healthyMeal = $0.entry { true } else { false } },
            cheatMeals: mine.count { if case .cheatMeal = $0.entry { true } else { false } })
    }
}
