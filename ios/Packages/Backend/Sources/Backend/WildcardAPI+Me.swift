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
            disclaimers: totals.disclaimers, topSport: topSport)
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

    /// Wears one of the member's titles on their card, or the latest won again for nil; answers
    /// the board as it stands. Safe to repeat.
    public func equip(title: String?) async throws(APIError) -> TitleBoard {
        let board = try await call {
            try await client.putMyEquippedTitle(body: .json(.init(version: ._1, title: title))).ok.body.json
        }
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
                squadPlace: card.squadPlace, joinedAt: card.joinedAt,
                totals: CheckInTotals(
                    trainedDays: card.trainedDays, healthyMeals: card.healthyMeals, cheatMeals: card.cheatMeals,
                    disclaimers: card.disclaimers,
                    topSport: try card.topSport.map { top throws(ContractsError) in
                        TopSport(activity: try Activity(top), checkIns: top.checkIns)
                    }),
                week: card.week.map { WeekCount(trainedDays: $0.trainedDays, plannedDays: $0.plannedDays) },
                board: try TitleBoard(card),
                schedule: try card.week.flatMap(MateSchedule.init))
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
            gifts: body.gifts.sorted { $0.givenAt < $1.givenAt }.filter { $0.openedAt != nil }.map(\.id))
    }

    /// 领取: puts an unlocked piece in the member's wardrobe, on every phone. Safe to repeat.
    public func claim(piece: String) async throws(APIError) {
        _ = try await call { try await client.claimPiece(path: .init(pieceId: piece)).ok }
    }

    /// Whether the one daily push at 6pm and the coach's pushes are on; each is until the member
    /// turns it off.
    public func pushSwitches() async throws(APIError) -> (dailyProgress: Bool, coach: Bool) {
        let settings = try await call { try await client.getMyPushSettings().ok.body.json }.settings
        return (settings.dailyProgress ?? true, settings.coach ?? true)
    }

    /// Turns the daily push on or off, leaving the coach's as it is. Safe to repeat.
    public func setDailyPush(_ isOn: Bool) async throws(APIError) {
        try await savePushSwitches(.init(dailyProgress: isOn))
    }

    /// Turns the coach's pushes on or off, leaving the daily push as it is. Safe to repeat.
    public func setCoachPush(_ isOn: Bool) async throws(APIError) {
        try await savePushSwitches(.init(coach: isOn))
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
    /// When they signed up; nil before they saved a profile.
    public let joinedAt: Date?
    public let totals: CheckInTotals
    /// Their own 本周 x/y; nil from a server that doesn't send it.
    public let week: WeekCount?
    public let board: TitleBoard
    /// Their 出赛表 this week; nil from a server that doesn't send it.
    public let schedule: MateSchedule?
}

extension MateSchedule {
    /// A squadmate's 出赛表 this week as the API sends it on their card; nil from a server that
    /// sends only the week's count.
    init?(_ wire: Components.Schemas.PlayerCard.WeekPayload) throws(ContractsError) {
        guard let start = wire.weekStart, let days = wire.days, let marks = wire.marks else { return nil }
        let planned = try [PlanDay](wire: days)
        guard planned.count == WeeklyPlan.dayCount else { throw .planLength(planned.count) }
        // A day's mark for each of the plan's days.
        guard marks.count == WeeklyPlan.dayCount else { throw .planLength(marks.count) }
        let read = try marks.map { mark throws(ContractsError) -> DayMark in
            switch mark.status {
            case .trained:
                guard let activity = try Activity(mark) else { throw .strayCustomSport }
                return .trained(activity)
            case .disclaimer: return .disclaimer
            case .none: return .none
            }
        }
        // A goal this build can't read is left out rather than the whole week.
        let fuel = (wire.fuelGoals ?? []).compactMap { try? FuelGoal($0) }
        let weekStart = try LocalDay(start)
        let first = try wire.firstWeek.map { day throws(ContractsError) in try LocalDay(day) }
        let today = try wire.today.map { day throws(ContractsError) in try LocalDay(day) }
        // Seven of each, checked above, is all it refuses.
        guard
            let schedule = try? MateSchedule(
                weekStart: weekStart, days: planned, marks: read, fuel: fuel, firstWeek: first,
                today: today)
        else { throw .planLength(planned.count) }
        self = schedule
    }
}
