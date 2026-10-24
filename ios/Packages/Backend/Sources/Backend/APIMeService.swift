import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import MeDomain

/// 我 over our API: the profile's character, the lifetime counts, the squad, the daily push
/// switch, and deleting the account.
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
            let character = try await api.me().profile?.character
            let totals = try await api.checkInTotals()
            let squad = try await api.mySquads().first
            // 本周 is counted against the plan the squad's today carries; no squad, no week. A today
            // that doesn't load leaves the week out rather than the whole page.
            var week: WeekCount?
            if let squad { week = try? await api.today(of: squad.id).myWeek.week }
            let dailyPushOn = try await api.dailyPushOn()
            return MeOverview(
                character: MeCharacter(
                    nickname: character?.nickname.text ?? "",
                    outfit: character.map { Outfit($0.look) } ?? Outfit([:]),
                    persona: character.map { Persona($0.look) } ?? .energetic),
                counts: LifetimeCounts(
                    trainedDays: totals.trainedDays, healthyMeals: totals.healthyMeals, cheatMeals: totals.cheatMeals,
                    disclaimers: totals.disclaimers),
                week: week, squadName: squad?.name, dailyPushOn: dailyPushOn)
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
                    )))
        }
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
}
