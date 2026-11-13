import APIContract
import Contracts
import Foundation
import MeDomain
import ScheduleDomain

// The member's own settings and records beyond the profile: lifetime counts, the push switch,
// the AI consent and deleting the account.
extension WildcardAPI {
    /// Everything the member ever checked in, by kind.
    public func checkInTotals() async throws(APIError) -> CheckInTotals {
        let totals = try await call { try await client.getMyCheckInTotals().ok.body.json }
        let topSport = try read { () throws(ContractsError) in
            try totals.topSport.map { top throws(ContractsError) in
                TopSport(activity: try Activity(top), checkIns: top.checkIns)
            }
        }
        return CheckInTotals(
            trainedDays: totals.trainedDays, healthyMeals: totals.healthyMeals, cheatMeals: totals.cheatMeals,
            disclaimers: totals.disclaimers, topSport: topSport, streaks: CardStreaks(totals.streaks))
    }

    /// The member's 练了 for days `from` through `last` (at most 371), by day, the earliest made
    /// first: 我's training record.
    public func trainings(from: LocalDay, through last: LocalDay) async throws(APIError) -> [TrainingDay] {
        let record = try await call {
            try await client.listMyTrainings(query: .init(from: from.description, to: last.description)).ok.body.json
        }
        return try read { () throws(ContractsError) in try record.trainings.map(TrainingDay.init) }
    }

    /// 外卡记录: the member's records, and how they stand in their squad, its squadmates named by
    /// `mates` (nil for one who left or made no character).
    public func records(
        mates: (MemberID) -> RecordMate
    ) async throws(APIError) -> WildcardRecords {
        let wire = try await call { try await client.getMyRecords().ok.body.json }
        return try read { () throws(ContractsError) in
            func streak(_ streak: Components.Schemas.RecordStreak?) throws(ContractsError) -> WildcardRecords.Streak? {
                try streak.map { streak throws(ContractsError) in
                    .init(days: streak.days, first: try LocalDay(streak.from), last: try LocalDay(streak.to))
                }
            }
            func count(_ wire: Components.Schemas.RecordMateCount?) throws(ContractsError) -> SquadStanding.MateCount? {
                try wire.map { wire throws(ContractsError) in
                    guard let id = UUID(uuidString: wire.memberId) else { throw .invalidID(wire.memberId) }
                    return .init(mate: mates(MemberID(id)), count: wire.count)
                }
            }
            let squad = try wire.squad.map { squad throws(ContractsError) in
                SquadStanding(
                    partner: try count(squad.partner),
                    cheersReceived: .init(count: squad.cheersReceived.count, top: try count(squad.cheersReceived.top)),
                    cheersGiven: .init(count: squad.cheersGiven.count, top: try count(squad.cheersGiven.top)),
                    // A kind this build doesn't know is left out, as the API asks.
                    firsts: squad.firsts.compactMap(SquadStanding.First.init(rawValue:)))
            }
            return WildcardRecords(
                trainedDays: wire.trainedDays, minutes: wire.minutes, longestMinutes: wire.longestMinutes,
                longestStreak: try streak(wire.longestStreak), mealStreak: try streak(wire.mealStreak),
                currentStreak: try streak(wire.currentStreak), currentMealStreak: try streak(wire.currentMealStreak),
                hours: wire.hours, weekdays: wire.weekdays,
                sports: try wire.sports.map { sport throws(ContractsError) in
                    .init(activity: try Activity(sport), days: sport.days)
                },
                sportCount: wire.sportCount, squad: squad)
        }
    }

    /// The member's badge board (徽章板): every weekly title they won, with its badge, and the one
    /// they wear.
    public func titleBoard() async throws(APIError) -> TitleBoard {
        let board = try await call { try await client.getMyTitles().ok.body.json }
        return try read { () throws(ContractsError) in try TitleBoard(board) }
    }

    /// Saves the birthday the member chose to give. Safe to repeat.
    public func save(_ birthday: Birthday) async throws(APIError) {
        _ = try await call {
            try await client.putMyBirthday(body: .json(.init(version: ._1, birthday: birthday.description))).ok
        }
    }

    /// Forgets the member's birthday. Safe to repeat.
    public func forgetBirthday() async throws(APIError) {
        try await call { _ = try await client.deleteMyBirthday().noContent }
    }

    /// Wears one of the member's titles or team badges on their card, or the latest title won
    /// again for nil; answers the board as it stands. Safe to repeat.
    public func equip(_ wearable: Wearable?) async throws(APIError) -> TitleBoard {
        let body: Components.Schemas.EquipTitle =
            switch wearable {
            case .title(let title): .init(version: ._1, title: title)
            case .teamBadge(let id): .init(version: ._1, title: nil, teamBadge: id)
            case nil: .init(version: ._1, title: nil)
            }
        let board = try await call { try await client.putMyEquippedTitle(body: .json(body)).ok.body.json }
        return try read { () throws(ContractsError) in try TitleBoard(board) }
    }

    /// A squadmate's player card, front and back.
    public func card(of member: MemberID, in squad: SquadID) async throws(APIError) -> SquadmateCard {
        let card = try await call {
            try await client.getSquadmateCard(
                path: .init(squadId: squad.description, memberId: member.description)
            ).ok.body.json
        }
        return try read { () throws(ContractsError) in
            SquadmateCard(
                character: try card.character.map(MemberCharacter.init),
                jerseyNumber: try card.jerseyNumber.map { number throws(ContractsError) in try JerseyNumber(number) },
                squadPlace: card.squadPlace,
                totals: CheckInTotals(
                    trainedDays: card.trainedDays, healthyMeals: card.healthyMeals, cheatMeals: card.cheatMeals,
                    disclaimers: card.disclaimers,
                    topSport: try card.topSport.map { top throws(ContractsError) in
                        TopSport(activity: try Activity(top), checkIns: top.checkIns)
                    }, streaks: CardStreaks(card.streaks)),
                week: WeekCount(trainedDays: card.week.trainedDays, plannedDays: card.week.plannedDays),
                board: try TitleBoard(card),
                schedule: try MateSchedule(card.week))
        }
    }

    /// The stores, props and pieces the member unlocked by training, the earliest first.
    public func unlocks() async throws(APIError) -> [Unlock] {
        try await unlockStanding().unlocks
    }

    /// What the member unlocked by training, the earliest first, and their 商店街 now.
    public func unlockStanding() async throws(APIError) -> UnlockStanding {
        let body = try await call { try await client.getMyUnlocks().ok.body.json }
        let reason = { (reason: Components.Schemas.UnlockReason) in
            (sports: reason.sports.compactMap(Sport.init(rawValue:)), checkIns: reason.checkIns)
        }
        let stores = body.unlocks.map { unlock in
            let why = reason(unlock.reason)
            return Unlock(
                kind: unlock.kind == .store ? .store : .prop, id: unlock.id, unlockedAt: unlock.unlockedAt,
                sports: why.sports, checkIns: why.checkIns)
        }
        let pieces = body.pieces.map { piece in
            let why = reason(piece.reason)
            return Unlock(
                kind: .piece, id: piece.id, unlockedAt: piece.unlockedAt, sports: why.sports, checkIns: why.checkIns)
        }
        return UnlockStanding(
            // Both lists are the earliest first; so is the whole.
            unlocks: (stores + pieces).sorted { $0.unlockedAt < $1.unlockedAt },
            claimed: Set(body.claimed.map(\.id)),
            stock: StreetStock(
                stores: body.shelf.stores.map { StreetStock.Store(id: $0.id, isOpen: $0.open, toGo: $0.checkInsToGo) },
                pieces: body.shelf.pieces.map { piece in
                    let state: StreetStock.State =
                        switch piece.state {
                        case .owned: .owned
                        case .available: .available
                        case .locked: .locked(toGo: piece.checkInsToGo ?? 1)
                        }
                    return StreetStock.Piece(
                        id: piece.id, store: piece.storeId, state: state,
                        sports: piece.sports.compactMap(Sport.init(rawValue:)))
                }),
            // What was given, worn without 领取: the coach's gifts once opened, then the team's pieces.
            gifts: body.gifts.sorted { $0.givenAt < $1.givenAt }.filter { $0.openedAt != nil }.map(\.id)
                + body.teamPieces.sorted { $0.givenAt < $1.givenAt }.map(\.id))
    }

    /// 领取: puts an unlocked piece in the member's wardrobe, on every phone. Safe to repeat.
    public func claim(piece: String) async throws(APIError) {
        _ = try await call { try await client.claimPiece(path: .init(pieceId: piece)).ok }
    }

    /// Whether the one daily push at 6pm, the coach's pushes and the push for a squadmate's 训练 are
    /// on; each is until the member turns it off.
    public func pushSwitches() async throws(APIError) -> (dailyProgress: Bool, coach: Bool, teammate: Bool) {
        let settings = try await call { try await client.getMyPushSettings().ok.body.json }.settings
        return (settings.dailyProgress ?? true, settings.coach ?? true, settings.teammate ?? true)
    }

    /// Turns the daily push on or off, leaving the coach's as it is. Safe to repeat.
    public func setDailyPush(_ isOn: Bool) async throws(APIError) {
        try await savePushSwitches(.init(dailyProgress: isOn))
    }

    /// Turns the coach's pushes on or off, leaving the daily push as it is. Safe to repeat.
    public func setCoachPush(_ isOn: Bool) async throws(APIError) {
        try await savePushSwitches(.init(coach: isOn))
    }

    /// Turns the push for a squadmate's 训练 on or off, leaving the others as they are. Safe to repeat.
    public func setTeammatePush(_ isOn: Bool) async throws(APIError) {
        try await savePushSwitches(.init(teammate: isOn))
    }

    private func savePushSwitches(_ settings: Components.Schemas.PushSettings.SettingsPayload) async throws(APIError) {
        _ = try await call {
            try await client.saveMyPushSettings(body: .json(.init(version: ._1, settings: settings))).ok
        }
    }

    /// Deletes the account and everything that is the member's, for good. `appleAuthorizationCode`,
    /// from confirming with Apple again, lets the API revoke the app's Apple tokens. Safe to repeat
    /// after a failure; signing out after is the caller's to do.
    public func deleteAccount(appleAuthorizationCode: String?) async throws(APIError) {
        _ = try await call {
            try await client.deleteMe(body: .json(.init(version: ._1, appleAuthorizationCode: appleAuthorizationCode)))
                .noContent
        }
    }

    /// Whether the member has agreed to the API's current AI consent copy.
    public func hasAgreedToAI() async throws(APIError) -> Bool {
        try await call { try await client.getMyAiConsent().ok.body.json }.current
    }

    /// Records that the member agreed to the AI consent copy the app showed. Safe to retry.
    public func agreeToAI(copyVersion: Int) async throws(APIError) {
        _ = try await call {
            try await client.putMyAiConsent(body: .json(.init(version: ._1, copyVersion: copyVersion))).ok
        }
    }
}

/// Everything a member ever checked in, by kind. Several 练了 on one day count once.
public struct CheckInTotals: Hashable, Sendable {
    public let trainedDays: Int
    public let healthyMeals: Int
    public let cheatMeals: Int
    public let disclaimers: Int
    /// The sport with the most 练了 (最常练); nil before the first.
    public let topSport: TopSport?
    /// The streaks still going.
    public let streaks: CardStreaks
}

extension CardStreaks {
    /// The API's streaks still going, a left-out (broken) one as 0.
    init(_ streaks: Components.Schemas.CurrentStreaks) {
        self.init(training: streaks.training?.days ?? 0, meals: streaks.meals?.days ?? 0)
    }
}

/// The sport a member logged the most 练了 for, and how many.
public struct TopSport: Hashable, Sendable {
    public let activity: Activity
    public let checkIns: Int
}

/// A squadmate's player card as the API sends it.
public struct SquadmateCard: Hashable, Sendable {
    /// Nil until they make their character.
    public let character: MemberCharacter?
    /// The number they picked; nil until they pick one.
    public let jerseyNumber: JerseyNumber?
    /// Their place in the squad, the first to join being 1.
    public let squadPlace: Int
    public let totals: CheckInTotals
    /// Their own 本周 x/y.
    public let week: WeekCount
    public let board: TitleBoard
    /// Their 出赛表 this week.
    public let schedule: MateSchedule
}

extension MateSchedule {
    /// A squadmate's 出赛表 this week as the API sends it on their card.
    init(_ wire: Components.Schemas.PlayerCard.WeekPayload) throws(ContractsError) {
        let (start, marks) = (wire.weekStart, wire.marks)
        let planned = try [PlanDay](wire: wire.days)
        guard planned.count == WeeklyPlan.dayCount else { throw .planLength(planned.count) }
        // A day's mark for each of the plan's days.
        guard marks.count == WeeklyPlan.dayCount else { throw .planLength(marks.count) }
        let read = try marks.map { mark throws(ContractsError) -> DayMark in
            switch mark.status {
            case .trained:
                guard let sports = try Activity.trained(on: mark) else { throw .strayCustomSport }
                return .trained(sports)
            case .disclaimer: return .disclaimer
            case .none: return .none
            }
        }
        // A goal this build can't read is left out rather than the whole week.
        let fuel = (wire.fuelGoals ?? []).compactMap { try? FuelGoal($0) }
        let weekStart = try LocalDay(start)
        // The squad's W1, so every card shows the squad's week number.
        let first = try LocalDay(wire.squadFirstWeek)
        let today = try LocalDay(wire.today)
        // Seven of each, checked above, is all it refuses.
        guard
            let schedule = try? MateSchedule(
                weekStart: weekStart, days: planned, marks: read, fuel: fuel, firstWeek: first,
                today: today)
        else { throw .planLength(planned.count) }
        self = schedule
    }
}
