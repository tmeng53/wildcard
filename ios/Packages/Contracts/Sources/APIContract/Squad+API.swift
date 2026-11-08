import Contracts
import Foundation

// Reading the squad, its today, the weekly plan and reactions from the API's wire types. Like
// the check-in's, reading checks everything `Contracts` checks.

extension Squad {
    public init(_ wire: Components.Schemas.Squad) throws(ContractsError) {
        self.init(
            id: try SquadID(wire: wire.id), name: wire.name, inviteCode: wire.inviteCode,
            members: try wire.members.map { member throws(ContractsError) in try MemberID(wire: member.userId) },
            captain: try wire.captain.map { captain throws(ContractsError) in try MemberID(wire: captain) })
    }
}

extension SquadScene {
    public init(_ wire: Components.Schemas.SquadScene) throws(ContractsError) {
        let pickers = try wire.pickers.members.map { member throws(ContractsError) in try MemberID(wire: member) }
        self.init(
            week: try LocalDay(wire.week), scene: SceneID(id: wire.sceneId, legacy: wire.scene.rawValue),
            pickers: wire.pickers.by == .crown ? .crown(pickers) : .captain(pickers.first),
            picked: try wire.picked.map { picked throws(ContractsError) in
                SquadScene.Pick(
                    scene: SceneID(id: picked.sceneId, legacy: picked.scene.rawValue),
                    picker: try picked.by.map { picker throws(ContractsError) in try MemberID(wire: picker) })
            },
            canPick: wire.canPick,
            // The scenes open this week (the winter one only in winter); one this build has no
            // art for isn't offered.
            history: wire.options.compactMap { option in
                SceneID(rawValue: option.sceneId).map { SceneHistory(scene: $0, weeksAgo: option.weeksAgo) }
            },
            takeover: wire.takeover ? wire.sceneId : nil)
    }
}

extension SceneID {
    /// The scene by its id, else by the five-scene field older builds read, else the gym. A
    /// scene this build wasn't made with keeps its id (its names, colours and pictures are data).
    init(id: String, legacy: String) {
        self = SceneID(rawValue: id) ?? SceneID(rawValue: legacy) ?? .gym
    }

    /// The body of `PUT /squads/{squadId}/weeks/{weekStart}/scene`.
    public func pick() -> Components.Schemas.ScenePick {
        .init(version: ._1, scene: rawValue)
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
                week: WeekCount(trainedDays: wire.me.week.trainedDays, plannedDays: wire.me.week.plannedDays)),
            squadWeek: WeekCount(trainedDays: wire.squadWeek.trainedDays, plannedDays: wire.squadWeek.plannedDays),
            squadDaysPerMember: wire.squadWeek.daysPerMember)
    }
}

extension SquadmateToday {
    init(_ wire: Components.Schemas.SquadToday.MembersPayloadPayload) throws(ContractsError) {
        self.init(
            member: try MemberID(wire: wire.member), catchphrase: try wire.catchphrase.map(Catchphrase.init),
            character: try wire.character.map(MemberCharacter.init),
            day: try LocalDay(wire.day),
            training: TrainingStatus(wire.training), latestMeal: wire.latestMeal.map(MealKind.init),
            plannedRest: wire.plannedRest, firstCheckInAt: wire.firstCheckInAt.map(Timestamp.init(wire:)),
            title: wire.title.map(WornTitle.init))
    }
}

extension WeeklyPlan {
    public init(_ wire: Components.Schemas.WeeklyPlan) throws(ContractsError) {
        try self.init(
            member: try MemberID(wire: wire.member), weekStart: try LocalDay(wire.weekStart),
            days: try [PlanDay](wire: wire.days))
    }
}

extension [PlanDay] {
    /// A plan's seven days as the API sends them, the week's first day first.
    public init(wire: Components.Schemas.PlanDays) throws(ContractsError) {
        self = try wire.map { day throws(ContractsError) in
            switch day {
            case .case1(let train):
                guard let sport = train.sport else { return .train(nil) }
                return .train(try Activity(sport: sport, customSport: train.customSport))
            case .case2: return .rest
            }
        }
    }
}

extension Components.Schemas.PlanDays {
    /// Seven days as the API takes them, the week's first day first.
    public init(_ days: [PlanDay]) {
        self = days.map { day in
            switch day {
            case .train(let activity):
                .case1(.init(kind: .train, sport: activity?.wireSport, customSport: activity?.wireCustomSport))
            case .rest: .case2(.init(kind: .rest))
            }
        }
    }
}

extension Components.Schemas.WeeklyPlanDraft {
    /// The body of `PUT /me/weekly-plans/{weekStart}` that saves these days, the week's first
    /// day first, with the week in the path.
    public init(_ days: [PlanDay]) {
        self.init(version: ._1, days: .init(days))
    }
}

extension Components.Schemas.PlanTemplateDraft {
    /// The body of `PUT /me/plan-template` that saves these days as the member's typical week.
    public init(_ days: [PlanDay]) {
        self.init(version: ._1, days: .init(days))
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

extension SquadPokes {
    public init(_ wire: Components.Schemas.SquadNudges) throws(ContractsError) {
        self.init(
            sent: Set(try wire.sent.map(MemberID.init(wire:))),
            received: try wire.received.map { received throws(ContractsError) in
                ReceivedPoke(from: try MemberID(wire: received.from), patAt: Timestamp(wire: received.at))
            })
    }
}

extension SquadWeeklyGoal {
    public init(_ wire: Components.Schemas.SquadWeeklyGoal) {
        self.init(
            daysPerMember: wire.daysPerMember, nextDaysPerMember: wire.nextDaysPerMember, canChange: wire.canChange,
            recent: wire.recent.map { Recent(weeks: $0.weeks, daysPerMember: $0.daysPerMember) })
    }

    /// The body of `PUT /squads/{squadId}/weekly-goal`.
    public static func change(to daysPerMember: Int) -> Components.Schemas.SquadWeeklyGoalChange {
        .init(version: ._1, daysPerMember: daysPerMember)
    }
}

extension SquadTimeZone {
    public init(_ wire: Components.Schemas.SquadTimeZone) {
        self.init(timeZone: wire.timeZone, nextTimeZone: wire.nextTimeZone, canChange: wire.canChange)
    }

    /// The body of `PUT /squads/{squadId}/time-zone`.
    public static func change(to timeZone: String) -> Components.Schemas.SquadTimeZoneChange {
        .init(version: ._1, timeZone: timeZone)
    }
}
