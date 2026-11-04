import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import MeDomain

/// 我 over our API: the profile's character and card number, the card's records, the squad, the
/// 每周模板's count, the daily push switch, and deleting the account.
public struct APIMeService: MeService {
    private let api: WildcardAPI
    private let beforeDeleting: @Sendable () async -> Void

    /// `beforeDeleting` runs once the member has confirmed, before the account goes: the app
    /// unregisters the phone from push there, while its session still works.
    public init(api: WildcardAPI, beforeDeleting: @escaping @Sendable () async -> Void = {}) {
        (self.api, self.beforeDeleting) = (api, beforeDeleting)
    }

    public func overview() async throws(MeError) -> MeOverview {
        try await me { () throws(APIError) in
            let member = try await api.me()
            let character = member.profile?.character
            let totals = try await api.checkInTotals()
            let squad = try await api.mySquads().first
            // 本周 is counted against the plan the squad's today carries; no squad, no week. A today
            // that doesn't load leaves the week out rather than the whole page.
            var week: WeekCount?
            if let squad { week = try? await api.today(of: squad.id).myWeek.week }
            // So does the badge board: the card shows none rather than no card.
            let board = (try? await api.titleBoard()) ?? .empty
            // Unlocks must load: an empty list would lock away stores and props the member earned.
            let standing = try await api.unlockStanding()
            let dailyPushOn = try await api.dailyPushOn()
            return MeOverview(
                character: MeCharacter(
                    nickname: character?.nickname.text ?? "",
                    outfit: character.map { Outfit($0.look) } ?? Outfit([:]),
                    persona: character.map { Persona($0.look) } ?? .energetic),
                joinedAt: member.joinedAt?.date,
                counts: LifetimeCounts(
                    trainedDays: totals.trainedDays, healthyMeals: totals.healthyMeals, cheatMeals: totals.cheatMeals,
                    disclaimers: totals.disclaimers),
                week: week, squadName: squad?.name, dailyPushOn: dailyPushOn,
                jerseyNumber: member.profile?.jerseyNumber,
                // Members are listed in the order they joined.
                squadPlace: squad?.members.firstIndex(of: member.id).map { $0 + 1 },
                board: board,
                unlocks: standing.unlocks,
                lockedPieces: standing.lockedPieces)
        }
    }

    /// Saves the card's number on the profile, keeping the rest of it.
    public func save(jerseyNumber: JerseyNumber) async throws(MeError) {
        try await me { () throws(APIError) in
            let profile = try await api.me().profile
            _ = try await api.save(
                Profile(
                    timeZone: profile?.timeZone ?? .current, catchphrase: profile?.catchphrase,
                    character: profile?.character, jerseyNumber: jerseyNumber))
        }
    }

    /// Saves the character on the profile, keeping the rest of it: the profile is saved whole.
    public func save(_ character: MeCharacter) async throws(MeError) {
        let nickname: Nickname
        do {
            nickname = try Nickname(character.nickname)
        } catch {
            throw .rejected
        }
        try await me { () throws(APIError) in
            let profile = try await api.me().profile
            _ = try await api.save(
                Profile(
                    timeZone: profile?.timeZone ?? .current, catchphrase: profile?.catchphrase,
                    character: MemberCharacter(
                        nickname: nickname, look: CharacterLook(outfit: character.outfit, persona: character.persona)
                    ), jerseyNumber: profile?.jerseyNumber))
        }
    }

    /// Wears one of the member's titles (nil: the latest won again).
    public func equip(_ title: String?) async throws(MeError) -> TitleBoard {
        try await me { () throws(APIError) in try await api.equip(title: title) }
    }

    public func setDailyPush(_ isOn: Bool) async throws(MeError) {
        try await me { () throws(APIError) in try await api.setDailyPush(isOn) }
    }

    public func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError) {
        await beforeDeleting()
        let code: String? =
            switch confirmation {
            case .apple(let authorizationCode): authorizationCode
            case .signedInSession: nil
            }
        try await me { () throws(APIError) in try await api.deleteAccount(appleAuthorizationCode: code) }
    }

    private func me<T>(_ call: () async throws(APIError) -> T) async throws(MeError) -> T {
        try await meCall(call)
    }
}

/// A squadmate's player card over our API, opened from their name on the home or in 小队设置.
public struct APISquadmateCards: SquadmateCards {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func card(of member: MemberID, in squad: SquadID) async throws(MeError) -> PlayerCardFace {
        try await meCall { () throws(APIError) in
            let card = try await api.card(of: member, in: squad)
            let character = card.character
            return PlayerCardFace(
                character: MeCharacter(
                    nickname: character?.nickname.text ?? "",
                    outfit: character.map { Outfit($0.look) } ?? Outfit([:]),
                    persona: character.map { Persona($0.look) } ?? .energetic),
                number: PlayerCardFace.number(picked: card.jerseyNumber, place: card.squadPlace),
                // The sheet fills in the squad's name it was opened from.
                squadName: nil, joinedAt: card.joinedAt,
                counts: LifetimeCounts(
                    trainedDays: card.totals.trainedDays, healthyMeals: card.totals.healthyMeals,
                    cheatMeals: card.totals.cheatMeals, disclaimers: card.totals.disclaimers),
                week: card.week, board: card.board)
        }
    }
}

/// Our API's failures as 我's.
private func meCall<T>(_ call: () async throws(APIError) -> T) async throws(MeError) -> T {
    do {
        return try await call()
    } catch .account(.signedOut), .account(.credentialRejected) {
        throw .signedOut
    } catch .refused, .unreadableResponse {
        throw .rejected
    } catch {
        throw .unavailable
    }
}
