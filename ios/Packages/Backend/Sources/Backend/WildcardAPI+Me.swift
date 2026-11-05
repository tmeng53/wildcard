import APIContract
import Contracts
import Foundation

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
                board: try TitleBoard(card))
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
                stores: body.shelf.stores.map { StreetStock.Store(id: $0.id, isOpen: $0.open) },
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
                }))
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
}
