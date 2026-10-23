import Contracts
import Foundation

// Reading the squad, its today, the weekly plan and reactions from the API's wire types. Like
// the check-in's, reading checks everything `Contracts` checks.

extension Squad {
    public init(_ wire: Components.Schemas.Squad) throws(ContractsError) {
        self.init(
            id: try SquadID(wire: wire.id), name: wire.name, inviteCode: wire.inviteCode,
            members: try wire.members.map { member throws(ContractsError) in try MemberID(wire: member.userId) })
    }
}

extension SquadToday {
    public init(_ wire: Components.Schemas.SquadToday) throws(ContractsError) {
        self.init(
            squad: try SquadID(wire: wire.squad),
            members: try wire.members.map { member throws(ContractsError) in try SquadmateToday(member) },
            today: TodayCounts(
                trained: wire.today.trained, disclaimer: wire.today.disclaimer, resting: wire.today.resting,
                everyoneTrained: wire.today.everyoneTrained),
            myWeek: MyWeek(
                firstDay: try LocalDay(wire.me.week.from), lastDay: try LocalDay(wire.me.week.to),
                week: WeekCount(trainedDays: wire.me.week.trainedDays, plannedDays: wire.me.week.plannedDays),
                lifetimeTrainedDays: wire.me.lifetimeTrainedDays),
            squadWeek: WeekCount(trainedDays: wire.squadWeek.trainedDays, plannedDays: wire.squadWeek.plannedDays))
    }
}

extension SquadmateToday {
    init(_ wire: Components.Schemas.SquadToday.MembersPayloadPayload) throws(ContractsError) {
        self.init(
            member: try MemberID(wire: wire.member), catchphrase: try wire.catchphrase.map(Catchphrase.init),
            day: try LocalDay(wire.day),
            training: TrainingStatus(wire.training), latestMeal: wire.latestMeal.map(MealKind.init),
            plannedRest: wire.plannedRest, firstCheckInAt: wire.firstCheckInAt.map(Timestamp.init(wire:)))
    }
}

extension WeeklyPlan {
    public init(_ wire: Components.Schemas.WeeklyPlan) throws(ContractsError) {
        try self.init(
            member: try MemberID(wire: wire.member), weekStart: try LocalDay(wire.weekStart),
            days: try wire.days.map { day throws(ContractsError) in
                switch day {
                case .case1(let train):
                    guard let sport = train.sport else { return .train(nil) }
                    return .train(try Activity(sport: sport, customSport: train.customSport))
                case .case2: return .rest
                }
            })
    }
}

extension Reaction {
    public init(_ wire: Components.Schemas.ReactionEntry) throws(ContractsError) {
        self.init(
            member: try MemberID(wire: wire.member), emoji: try Emoji(wire.emoji),
            reactedAt: Timestamp(wire: wire.reactedAt))
    }

    public init(_ wire: Components.Schemas.Reaction) throws(ContractsError) {
        self.init(
            member: try MemberID(wire: wire.member), emoji: try Emoji(wire.emoji),
            reactedAt: Timestamp(wire: wire.reactedAt))
    }
}

extension TrainingStatus {
    init(_ wire: Components.Schemas.SquadToday.MembersPayloadPayload.TrainingPayload) {
        self =
            switch wire {
            case .trained: .trained
            case .disclaimer: .disclaimer
            case .notCheckedIn: .notCheckedIn
            }
    }
}

extension MealKind {
    init(_ wire: Components.Schemas.SquadToday.MembersPayloadPayload.LatestMealPayload) {
        self =
            switch wire {
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            }
    }
}

extension Emoji {
    /// The body of `PUT /check-ins/{id}/reactions/mine`.
    public var draft: Components.Schemas.ReactionDraft { .init(version: ._1, emoji: text) }
}
