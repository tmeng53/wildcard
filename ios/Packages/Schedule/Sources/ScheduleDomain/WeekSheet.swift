import Contracts
import Foundation

/// One week of the 出赛表 as the server holds it: the plan, how each day went, the titles the
/// squad's weekly awards gave the member and the week's scene.
public struct WeekSheet: Hashable, Sendable {
    /// The week's Monday.
    public let weekStart: LocalDay
    /// Seven days, Monday first.
    public var plan: [PlanDay]
    /// Seven days, Monday first: what the member checked in each day.
    public let marks: [DayMark]
    /// The titles (头衔) the week's awards gave the member, best first. Empty until the awards
    /// are written on Sunday night, and for a week they didn't check in.
    public let titles: [AwardTitle]
    /// The week's own scene: for a week that is over, the one its 战报 names (nil without one);
    /// this week's once Sunday's 战报 opened next week's pick; next week's once picked. Nil
    /// otherwise.
    public let scene: SceneID?

    public init(
        weekStart: LocalDay, plan: [PlanDay], marks: [DayMark], titles: [AwardTitle] = [],
        scene: SceneID? = nil
    ) throws(ScheduleError) {
        guard plan.count == WeeklyPlan.dayCount, marks.count == WeeklyPlan.dayCount else { throw .refused }
        self.weekStart = weekStart
        self.plan = plan
        self.marks = marks
        self.titles = titles
        self.scene = scene
    }

    /// What the member trains at on day `index` (Monday 0): the sport the poster shows that day
    /// (`plan`'s, the board's while it changes, else the latest 练了's); nil for a rest day with
    /// no 练了.
    public func activity(on index: Int, plan: [PlanDay]) -> Activity? {
        guard marks.indices.contains(index), plan.indices.contains(index) else { return nil }
        guard case .train(let activity?) = marks[index].face(of: plan[index]).shown else { return nil }
        return activity
    }

    /// The days the plan trains.
    public var plannedDays: Int { plan.count { $0 != .rest } }

    /// The days with a 练了, planned or not: what 本周 x/y counts, as the home's my week does.
    public var trainedDays: Int { marks.count(where: \.isTrained) }
}

/// How a day went: one status a day, a 练了 over a 请假条.
public enum DayMark: Hashable, Sendable {
    /// One 练了 or more, with the sports they logged, the latest last (never empty).
    case trained([Activity])
    case disclaimer
    case none

    public var isTrained: Bool {
        if case .trained = self { true } else { false }
    }

    /// What a day's row says and how it is marked (Tracy, 2026-11-08): the plan stays what the
    /// member made it, so a day planned as a sport shows that sport, ticked only when a 练了 that
    /// day logged it. A day planned as rest, or with no sport picked, that was trained anyway
    /// shows the latest sport trained, ticked.
    public func face(of plan: PlanDay) -> (shown: PlanDay, mark: DayMark) {
        guard case .trained(let sports) = self else { return (plan, self) }
        if case .train(let planned?) = plan {
            return (plan, sports.contains(planned) ? self : .none)
        }
        guard let latest = sports.last else { return (plan, .none) }
        return (.train(latest), self)
    }
}

/// A title (头衔) the weekly awards gave the member, its award line (颁奖词) and its badge.
public struct AwardTitle: Hashable, Sendable {
    public let title: String
    public let speech: String
    /// Drawn in its own colour, as the badge board draws it.
    public let badge: TitleBadge

    public init(title: String, speech: String, badge: TitleBadge = .plain) {
        (self.title, self.speech, self.badge) = (title, speech, badge)
    }
}
