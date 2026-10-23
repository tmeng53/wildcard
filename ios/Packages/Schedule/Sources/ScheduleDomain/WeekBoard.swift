import Contracts

/// Where a week stands from the member's today.
public enum WeekTense: Hashable, Sendable {
    /// Over: read-only.
    case past
    /// This week: only days still to come change, and its rest days only move.
    case current
    /// Next week or later: every day changes freely.
    case upcoming
}

/// One week's plan as the poster edits it, with the rules for what a tap does. A value: the
/// store keeps it and saves its days after each change.
///
/// - Next week: tap a day to select it, then pick its sport or 休息 under the poster.
/// - This week, a day still to come: tap a training day to pick another sport (never 休息, so
///   the rest days keep their number); tap a rest day to lift it, then a training day to swap
///   the two. Today and the days before it stay as they are.
/// - A past week: nothing changes.
public struct WeekBoard: Hashable, Sendable {
    /// What the board has hold of.
    public enum Focus: Hashable, Sendable {
        case none
        /// A day whose sport is being picked.
        case selected(Int)
        /// A rest day of this week, about to swap with a training day.
        case lifted(Int)
    }

    /// What a tap did, so the screen can answer with the right haptic.
    public enum TapOutcome: Hashable, Sendable {
        /// The day can't change: past, or today or before in this week.
        case locked
        case selected
        case lifted
        /// The lifted rest day and a training day swapped.
        case swapped
        /// Let go of the selected or lifted day.
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
        case .current: return index > (today ?? WeeklyPlan.dayCount)
        }
    }

    /// While a rest day is lifted: the training days it can swap with.
    public func isSwapTarget(_ index: Int) -> Bool {
        guard case .lifted = focus, isEditable(index) else { return false }
        return days[index] != .rest
    }

    /// Whether 休息 is among the picks for the selected day: only in a week that hasn't started.
    public var offersRest: Bool { tense == .upcoming }

    public var plannedDays: Int { days.count { $0 != .rest } }

    @discardableResult
    public mutating func tap(_ index: Int) -> TapOutcome {
        guard isEditable(index) else { return .locked }
        switch (tense, focus) {
        case (.current, .lifted(let lifted)) where lifted == index:
            focus = .none
            return .released
        case (.current, .lifted(let lifted)) where days[index] != .rest:
            days[lifted] = days[index]
            days[index] = .rest
            focus = .none
            return .swapped
        case (.current, _) where days[index] == .rest:
            focus = .lifted(index)
            return .lifted
        case (_, .selected(let selected)) where selected == index:
            focus = .none
            return .released
        default:
            focus = .selected(index)
            return .selected
        }
    }

    /// Lets go of whatever the board has hold of.
    public mutating func release() {
        focus = .none
    }

    /// Makes the selected day a training day of `activity`; nothing without a selected day.
    public mutating func pick(_ activity: Activity) {
        guard case .selected(let index) = focus else { return }
        days[index] = .train(activity)
    }

    /// Makes the selected day a rest day, in a week that hasn't started.
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
