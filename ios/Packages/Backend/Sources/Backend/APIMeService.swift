import APIContract
import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import MeDomain

/// 我 over our API: the profile's character and card number, the card's records, the squad, the
/// 我的每周计划's count, the daily push switch, and deleting the account.
public struct APIMeService: MeService {
    private let api: WildcardAPI
    private let beforeDeleting: @Sendable () async -> Void
    private let now: @Sendable () -> Date

    /// `beforeDeleting` runs once the member has confirmed, before the account goes: the app
    /// unregisters the phone from push there, while its session still works. `now` says which
    /// week is this week, on the member's own clock.
    public init(
        api: WildcardAPI, beforeDeleting: @escaping @Sendable () async -> Void = {},
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        (self.api, self.beforeDeleting, self.now) = (api, beforeDeleting, now)
    }

    public func overview() async throws(MeError) -> MeOverview {
        try await me { () throws(APIError) in
            let member = try await api.me()
            let character = member.profile?.character
            let totals = try await api.checkInTotals()
            let squad = try await api.mySquad()
            // 本周 is counted against the plan the squad's today carries; no squad, no week. A today
            // that doesn't load leaves the week out rather than the whole page.
            var week: WeekCount?
            if let squad { week = try? await api.today(of: squad.id).myWeek.week }
            // So does the badge board: the card shows none rather than no card.
            let board = (try? await api.titleBoard()) ?? .empty
            // Unlocks must load: an empty list would lock away stores and props the member earned.
            let standing = try await api.unlockStanding()
            let push = try await api.pushSwitches()
            // The 出赛表 tile's days: the tile shows the count alone when they don't load.
            let timeZone = member.profile?.timeZone ?? .current
            let glance = try? await weekGlance(in: timeZone)
            // 训练记录: the page leaves the heatmap out when it doesn't load.
            let record = try? await trainingRecord(in: timeZone)
            return MeOverview(
                character: MeCharacter(
                    nickname: character?.nickname.text ?? "",
                    outfit: character.map { Outfit($0.look) } ?? Outfit([:]),
                    persona: character.map { Persona($0.look) } ?? .energetic),
                joinedAt: member.joinedAt?.date,
                counts: LifetimeCounts(
                    trainedDays: totals.trainedDays, healthyMeals: totals.healthyMeals, cheatMeals: totals.cheatMeals,
                    disclaimers: totals.disclaimers),
                week: week, squadName: squad?.name, dailyPushOn: push.dailyProgress, coachPushOn: push.coach,
                jerseyNumber: member.profile?.jerseyNumber,
                // Members are listed in the order they joined.
                squadPlace: squad?.members.firstIndex(of: member.id).map { $0 + 1 },
                board: board,
                unlocks: standing.unlocks,
                stock: standing.stock, claimed: standing.claimed, weekGlance: glance,
                record: record)
        }
    }

    /// 外卡记录, its squadmates named and drawn from the squad's today. A today that doesn't load
    /// leaves them as members without a character.
    public func records() async throws(MeError) -> WildcardRecords {
        try await me { () throws(APIError) in
            var characters: [MemberID: MemberCharacter] = [:]
            if let squad = try await api.mySquad(), let today = try? await api.today(of: squad.id) {
                for member in today.members {
                    characters[member.member] = member.character
                }
            }
            return try await api.records { member in
                RecordMate(
                    member: member,
                    character: characters[member].map { character in
                        MeCharacter(
                            nickname: character.nickname.text, outfit: Outfit(character.look),
                            persona: Persona(character.look))
                    })
            }
        }
    }

    /// This week's plan and the days with a 练了, numbered as the 出赛表 numbers weeks.
    private func weekGlance(in timeZone: TimeZone) async throws(APIError) -> WeekGlance {
        let today = LocalDay(at: now(), in: timeZone)
        let monday = today.weekStart
        let wire = try await api.weeklyPlanWire(weekStart: monday)
        let plan = try api.read { () throws(ContractsError) in try WeeklyPlan(wire) }
        let firstWeek = try wire.firstWeek.map { text throws(APIError) in
            try api.read { () throws(ContractsError) in try LocalDay(text) }
        }
        let checkIns = try await api.myCheckIns(from: monday, through: monday.adding(days: 6))
        let trained = Set(
            checkIns.compactMap { checkIn -> Int? in
                guard case .trained = checkIn.entry else { return nil }
                return checkIn.day.weekday - 1
            })
        return WeekGlance(
            number: monday.weekNumber(since: firstWeek ?? monday), plan: plan.days, trainedDays: trained,
            today: today.weekday - 1)
    }

    /// The member's last weeks of 练了, ending with this week on their own clock.
    private func trainingRecord(in timeZone: TimeZone) async throws(APIError) -> TrainingRecord {
        let today = LocalDay(at: now(), in: timeZone)
        let trainings = try await api.trainings(from: TrainingRecord.firstDay(today: today), through: today)
        return TrainingRecord(today: today, trainings: trainings)
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

    public func claim(piece: String) async throws(MeError) {
        try await me { () throws(APIError) in try await api.claim(piece: piece) }
    }

    public func setDailyPush(_ isOn: Bool) async throws(MeError) {
        try await me { () throws(APIError) in try await api.setDailyPush(isOn) }
    }

    public func setCoachPush(_ isOn: Bool) async throws(MeError) {
        try await me { () throws(APIError) in try await api.setCoachPush(isOn) }
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
                week: card.week, board: card.board,
                schedule: card.schedule)
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
