import Contracts

/// Where a week stands from the member's today.
public enum WeekTense: Hashable, Sendable {
    /// Over: read-only.
    case past
    /// This week: the days still to come change freely; today's sport changes, and a rest today
    /// may become a training day; the days before today stay.
    case current
    /// Next week or later: every day changes freely.
    case upcoming
}

/// One week's plan as the poster edits it, with the rules for what a tap does. A value: the
/// store keeps it and saves its days after each change.
///
/// - Next week, or a day still to come this week: tap a day to select it, then pick its sport
///   or 休息 under the poster. Every change is saved, and the server logs each one.
/// - This week, today picks a sport, never 休息: a rest today becomes a training day. The days
///   before today stay as they are.
/// - A past week: nothing changes.
public struct WeekBoard: Hashable, Sendable {
    /// What the board has hold of.
    public enum Focus: Hashable, Sendable {
        case none
        /// A day whose sport or rest is being picked.
        case selected(Int)
    }

    /// What a tap did, so the screen can answer with the right haptic.
    public enum TapOutcome: Hashable, Sendable {
        /// The day can't change: past, or before today in this week.
        case locked
        case selected
        /// Let go of the selected day.
        case released
    }

    public let weekStart: LocalDay
    public let tense: WeekTense
    /// Today's index in `days` in the current week; nil in any other.
    public let today: Int?
    public private(set) var days: [PlanDay]
    public private(set) var focus = Focus.none

    /// - Parameter today: the member's day now.
    public init(weekStart: LocalDay, days: [PlanDay], today: LocalDay) {
        self.weekStart = weekStart
        self.days = days
        if weekStart > today {
            tense = .upcoming
            self.today = nil
        } else if weekStart.adding(days: WeeklyPlan.dayCount) <= today {
            tense = .past
            self.today = nil
        } else {
            tense = .current
            self.today = today.weekday - 1
        }
    }

    /// Whether the day may change at all.
    public func isEditable(_ index: Int) -> Bool {
        guard days.indices.contains(index) else { return false }
        switch tense {
        case .past: return false
        case .upcoming: return true
        case .current:
            guard let today else { return false }
            return index >= today
        }
    }

    /// Whether 休息 is among the picks for the selected day: any day but today.
    public var offersRest: Bool {
        guard case .selected(let index) = focus else { return false }
        return index != today
    }

    public var plannedDays: Int { days.count { $0 != .rest } }

    @discardableResult
    public mutating func tap(_ index: Int) -> TapOutcome {
        guard isEditable(index) else { return .locked }
        if focus == .selected(index) {
            focus = .none
            return .released
        }
        focus = .selected(index)
        return .selected
    }

    /// Lets go of the selected day.
    public mutating func release() {
        focus = .none
    }

    /// Makes the selected day a training day of `activity`; nothing without a selected day.
    public mutating func pick(_ activity: Activity) {
        guard case .selected(let index) = focus else { return }
        days[index] = .train(activity)
    }

    /// Makes the selected day a rest day; nothing without a selected day, or for today.
    public mutating func rest() {
        guard offersRest, case .selected(let index) = focus else { return }
        days[index] = .rest
    }

    /// Puts days back as the server has them, keeping hold of nothing.
    public mutating func reset(to days: [PlanDay]) {
        self.days = days
        focus = .none
    }
}
