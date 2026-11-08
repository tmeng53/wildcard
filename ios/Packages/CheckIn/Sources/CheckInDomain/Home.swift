import Contracts
import Foundation

/// What the home screen and 打卡 read: the member, their squad and its today, this week's plan
/// and the squad's recent check-ins. A copy is kept on the device, so the home opens offline.
public struct Home: Hashable, Sendable {
    /// The signed-in member.
    public let member: MemberID
    /// The member's profile time zone, where their day and week run.
    public let timeZone: TimeZone
    /// The member's squad: a member is in one at most.
    public let squad: Squad
    public var today: SquadToday
    /// The member's plan for this week.
    public let plan: WeeklyPlan
    /// The squad's check-ins from two days before the member's day to two days after, so every
    /// member's own today is in it whatever their time zone (UTC+14 and UTC−12, with the 3am
    /// grace, are up to two days apart), and the member's own since Monday, whichever squads
    /// they went to; oldest first.
    public var checkIns: [CheckIn]

    /// The member's own posts today kept to themselves show in their row (`showingMine`).
    public init(
        member: MemberID, timeZone: TimeZone, squad: Squad, today: SquadToday,
        plan: WeeklyPlan, checkIns: [CheckIn]
    ) {
        self.member = member
        self.timeZone = timeZone
        self.squad = squad
        self.today = checkIns.filter { $0.member == member }.reduce(today) { $0.showingMine($1) }
        self.plan = plan
        self.checkIns = checkIns
    }

    /// The member's own entry in the squad's today.
    public var mine: SquadmateToday? {
        today.members.first { $0.member == member }
    }

    /// `member`'s check-ins to this squad on their own today, oldest first: what tapping their
    /// character shows. A teammate's sent only to another squad doesn't show here, as on the
    /// server; the member's own all do, wherever they were shared.
    public func todaysCheckIns(of member: MemberID) -> [CheckIn] {
        guard let day = today.members.first(where: { $0.member == member })?.day else { return [] }
        return checkIns.filter {
            $0.member == member && $0.day == day && (member == self.member || $0.audience.squads.contains(squad.id))
        }
    }

    /// The member's `day` as `squad` sees it, with `pending` posts still to go out. Their row
    /// is it unless one of that day's posts wasn't shared here; then it is what their posts
    /// shared here add up to. The squad's counts follow this, never a row a private post moved.
    public func squadSees(on day: LocalDay, plus pending: some Sequence<PendingCheckIn> = []) -> TrainingStatus {
        let posts =
            checkIns.filter { $0.member == member && $0.day == day }.map {
                (squads: $0.audience.squads, kind: Kind($0.entry))
            }
            + pending.filter { $0.member == member && $0.day == day }.map {
                (squads: $0.audience.squads, kind: Kind($0.draft))
            }
        if let row = today.members.first(where: { $0.member == member && $0.day == day }),
            posts.allSatisfy({ $0.squads.contains(squad.id) })
        {
            return row.training
        }
        let shared = posts.filter { $0.squads.contains(squad.id) }.map(\.kind)
        if shared.contains(.trained) { return .trained }
        return shared.contains(.disclaimer) ? .disclaimer : .notCheckedIn
    }

    private enum Kind {
        /// `other`: a meal or a 休息, neither of which changes how the squad sees the day.
        case trained, disclaimer, other

        init(_ entry: CheckIn.Entry) {
            switch entry {
            case .trained: self = .trained
            case .disclaimer(let note): self = note.restDay ? .other : .disclaimer
            case .healthyMeal, .cheatMeal: self = .other
            }
        }

        init(_ draft: CheckInDraft) {
            switch draft {
            case .trained: self = .trained
            case .disclaimer(let note): self = note.restDay ? .other : .disclaimer
            case .healthyMeal, .cheatMeal: self = .other
            }
        }
    }

    /// The sport `member` trained today, from their latest 练了: what their character plays.
    public func todaysSport(of member: MemberID) -> Activity? {
        todaysCheckIns(of: member).last { if case .trained = $0.entry { true } else { false } }
            .flatMap { if case .trained(let training) = $0.entry { training.activity } else { nil } }
    }

    /// How long someone who trained today eats a meal posted after it, before going back to
    /// their sport (Tracy, 2026-11-08).
    public static let mealAfterTraining = Duration.seconds(3600)

    /// The post `member`'s character acts out at `now`: their latest today, except that a meal
    /// after a 练了 lasts `mealAfterTraining`, then they go back to training.
    func todaysShownPost(of member: MemberID, at now: Timestamp) -> CheckIn? {
        let posts = todaysCheckIns(of: member)
        guard let last = posts.last, let ends = mealEnds(of: member) else { return posts.last }
        return now < ends ? last : posts.last { if case .trained = $0.entry { true } else { false } }
    }

    /// When the meal `member` eats after a 练了 today ends, while their latest post is one; nil
    /// when they didn't train first, so their meal lasts all day.
    public func mealEnds(of member: MemberID) -> Timestamp? {
        let posts = todaysCheckIns(of: member)
        guard let last = posts.last, Self.meal(last.entry) != nil,
            posts.contains(where: { if case .trained = $0.entry { true } else { false } })
        else { return nil }
        let length = Int64(Self.mealAfterTraining / .milliseconds(1))
        return Timestamp(millisecondsSince1970: last.createdAt.millisecondsSince1970 + length)
    }

    /// The meal `member` is eating at `now`: their latest post today, when it is a 健康餐 or
    /// 坦白放纵餐 (Tracy, 2026-11-04), for an hour when they trained before it.
    public func todaysMeal(of member: MemberID, at now: Timestamp) -> MealKind? {
        todaysShownPost(of: member, at: now).flatMap { Self.meal($0.entry) }
    }

    private static func meal(_ entry: CheckIn.Entry) -> MealKind? {
        switch entry {
        case .healthyMeal: .healthyMeal
        case .cheatMeal: .cheatMeal
        case .trained, .disclaimer: nil
        }
    }

    /// The words of the post `member`'s character acts out at `now`, if it has any: the second
    /// line of their bubble, under what that post says they are doing.
    public func todaysCaption(of member: MemberID, at now: Timestamp) -> String? {
        switch todaysShownPost(of: member, at: now)?.entry {
        case .trained(let training)?: training.caption?.text
        case .healthyMeal(let meal)?, .cheatMeal(let meal)?: meal.caption?.text
        case .disclaimer?, nil: nil
        }
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
        switch squadSees(on: old.day) {
        case .trained: home.today.today.trained -= 1
        case .disclaimer: home.today.today.disclaimer -= 1
        case .notCheckedIn: if old.plannedRest { home.today.today.resting -= 1 }
        }
        let plannedRest = isRestDay(day)
        if plannedRest { home.today.today.resting += 1 }
        home.today.members.remove(at: index)
        home.today.members.append(
            SquadmateToday(
                member: member, catchphrase: old.catchphrase, character: old.character, day: day,
                training: .notCheckedIn, latestMeal: nil,
                plannedRest: plannedRest, firstCheckInAt: nil, title: old.title))
        if day > today.myWeek.lastDay {
            home.today.myWeek = MyWeek(
                firstDay: day.weekStart, lastDay: day.weekStart.adding(days: 6),
                week: WeekCount(trainedDays: 0, plannedDays: today.myWeek.week.plannedDays))
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

    /// 常用运动: the sports the member logged most recently, newest first, then this week's
    /// planned ones (which start as the sports they chose at sign-up), at most `limit`.
    public func recentActivities(limit: Int = 6) -> [Activity] {
        let logged: [Activity] = checkIns.reversed().compactMap { checkIn in
            guard checkIn.member == member, case .trained(let training) = checkIn.entry else { return nil }
            return training.activity
        }
        let planned: [Activity] = plan.days.compactMap { day in
            if case .train(let activity?) = day { activity } else { nil }
        }
        var seen: [Activity] = []
        for activity in logged + planned where !seen.contains(activity) { seen.append(activity) }
        return Array(seen.prefix(limit))
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
