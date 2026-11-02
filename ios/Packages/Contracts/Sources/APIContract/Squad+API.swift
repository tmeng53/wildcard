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
            week: try LocalDay(wire.week), scene: try SceneID(wire: wire.scene.rawValue),
            pickers: wire.pickers.by == .crown ? .crown(pickers) : .captain(pickers.first),
            picked: try wire.picked.map { picked throws(ContractsError) in
                SquadScene.Pick(
                    scene: try SceneID(wire: picked.scene.rawValue),
                    picker: try picked.by.map { picker throws(ContractsError) in try MemberID(wire: picker) })
            },
            canPick: wire.canPick,
            history: try wire.scenes.map { scene throws(ContractsError) in
                SceneHistory(scene: try SceneID(wire: scene.scene.rawValue), weeksAgo: scene.weeksAgo)
            })
    }
}

extension SceneID {
    init(wire: String) throws(ContractsError) {
        guard let scene = SceneID(rawValue: wire) else { throw .unknownScene(wire) }
        self = scene
    }

    /// The body of `PUT /squads/{squadId}/weeks/{weekStart}/scene`; a scene the API doesn't know
    /// is refused here rather than sent as another one.
    public func pick() throws(ContractsError) -> Components.Schemas.ScenePick {
        guard let scene = Components.Schemas.ScenePick.ScenePayload(rawValue: rawValue) else {
            throw .unknownScene(rawValue)
        }
        return .init(version: ._1, scene: scene)
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
            squadWeek: WeekCount(trainedDays: wire.squadWeek.trainedDays, plannedDays: wire.squadWeek.plannedDays))
    }
}

extension SquadmateToday {
    init(_ wire: Components.Schemas.SquadToday.MembersPayloadPayload) throws(ContractsError) {
        self.init(
            member: try MemberID(wire: wire.member), catchphrase: try wire.catchphrase.map(Catchphrase.init),
            character: try wire.character.map(MemberCharacter.init),
            day: try LocalDay(wire.day),
            training: TrainingStatus(wire.training), latestMeal: wire.latestMeal.map(MealKind.init),
            plannedRest: wire.plannedRest, firstCheckInAt: wire.firstCheckInAt.map(Timestamp.init(wire:)))
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
