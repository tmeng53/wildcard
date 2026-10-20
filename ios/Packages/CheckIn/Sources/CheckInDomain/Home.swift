import Contracts
import Foundation

/// What the home screen and 打卡 read: the member, their squad and its today, this week's plan
/// and the squad's recent check-ins. A copy is kept on the device, so the home opens offline.
public struct Home: Hashable, Sendable {
    /// The signed-in member.
    public let member: MemberID
    /// The member's profile time zone, where their day and week run.
    public let timeZone: TimeZone
    /// The squad the app shows: the earliest joined.
    public let squad: Squad
    public var today: SquadToday
    /// The member's plan for this week.
    public let plan: WeeklyPlan
    /// The squad's check-ins from two days before the member's day to two days after, so every
    /// member's own today is in it whatever their time zone (UTC+14 and UTC−12, with the 3am
    /// grace, are up to two days apart), and the member's own since Monday, whichever squads
    /// they went to; oldest first.
    public var checkIns: [CheckIn]

    public init(
        member: MemberID, timeZone: TimeZone, squad: Squad, today: SquadToday, plan: WeeklyPlan, checkIns: [CheckIn]
    ) {
        self.member = member
        self.timeZone = timeZone
        self.squad = squad
        self.today = today
        self.plan = plan
        self.checkIns = checkIns
    }

    /// The member's own entry in the squad's today.
    public var mine: SquadmateToday? {
        today.members.first { $0.member == member }
    }

    /// `member`'s check-ins to this squad on their own today, oldest first: what tapping their
    /// character shows. One sent only to another squad doesn't show here, as on the server.
    public func todaysCheckIns(of member: MemberID) -> [CheckIn] {
        guard let day = today.members.first(where: { $0.member == member })?.day else { return [] }
        return checkIns.filter { $0.member == member && $0.day == day && $0.audience.squads.contains(squad.id) }
    }

    /// The sport `member` trained today, from their latest 练了: what their character plays.
    public func todaysSport(of member: MemberID) -> Activity? {
        todaysCheckIns(of: member).last { if case .trained = $0.entry { true } else { false } }
            .flatMap { if case .trained(let training) = $0.entry { training.activity } else { nil } }
    }

    /// The text of `member`'s 请假条 today, if they posted one: what their character holds up.
    public func todaysDisclaimer(of member: MemberID) -> String? {
        todaysCheckIns(of: member).lazy.compactMap {
            if case .disclaimer(let note) = $0.entry { note.text } else { nil }
        }
        .first
    }

    /// The home with the member's own row moved on to `day` when the copy is from an earlier
    /// one: after 3am, or opened offline on a new day. Their old status leaves today's counts,
    /// and in a new week their week and the squad's start from no trained days. Teammates'
    /// rows wait for the next load.
    public func rolled(to day: LocalDay) -> Home {
        guard let index = today.members.firstIndex(where: { $0.member == member }), today.members[index].day < day
        else { return self }
        var home = self
        let old = today.members[index]
        switch old.training {
        case .trained: home.today.today.trained -= 1
        case .disclaimer: home.today.today.disclaimer -= 1
        case .notCheckedIn: if old.plannedRest { home.today.today.resting -= 1 }
        }
        let plannedRest = isRestDay(day)
        if plannedRest { home.today.today.resting += 1 }
        home.today.members.remove(at: index)
        home.today.members.append(
            SquadmateToday(
                member: member, catchphrase: old.catchphrase, day: day, training: .notCheckedIn, latestMeal: nil,
                plannedRest: plannedRest, firstCheckInAt: nil))
        if day > today.myWeek.lastDay {
            home.today.myWeek = MyWeek(
                firstDay: day.weekStart, lastDay: day.weekStart.adding(days: 6),
                week: WeekCount(trainedDays: 0, plannedDays: today.myWeek.week.plannedDays),
                lifetimeTrainedDays: today.myWeek.lifetimeTrainedDays)
            home.today.squadWeek.trainedDays = 0
        }
        home.today.today.everyoneTrained =
            home.today.today.trained > 0 && home.today.members.allSatisfy { $0.training == .trained || $0.plannedRest }
        return home
    }

    /// Whether this week's plan rests on `day`; false for a day outside it.
    func isRestDay(_ day: LocalDay) -> Bool {
        let offset = day.weekday - 1
        return day.weekStart == plan.weekStart && plan.days.indices.contains(offset) && plan.days[offset] == .rest
    }

    /// The sport a new 练了 starts with: today's in the plan, else the member's latest 练了.
    public func suggestedActivity(on day: LocalDay) -> Activity? {
        let offset = day.weekday - 1
        if day.weekStart == plan.weekStart, plan.days.indices.contains(offset),
            case .train(let planned?) = plan.days[offset]
        {
            return planned
        }
        return checkIns.last { checkIn in
            guard checkIn.member == member, case .trained = checkIn.entry else { return false }
            return true
        }
        .flatMap { checkIn in
            if case .trained(let training) = checkIn.entry { training.activity } else { nil }
        }
    }
}
