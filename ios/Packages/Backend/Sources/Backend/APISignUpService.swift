import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import OnboardingDomain

/// Sign-up over our API: the squad step makes or joins a squad, 角色和昵称 saves the character
/// on the profile and 一周练几天？ saves this week's plan.
public struct APISignUpService: SignUpService {
    private let api: WildcardAPI
    private let now: @Sendable () -> Date
    private let newID: @Sendable () -> UUID

    /// - Parameters:
    ///   - now: the clock this week's plan is read from.
    ///   - newID: the id a new squad is made under, so a retry makes the same squad.
    public init(
        api: WildcardAPI, now: @escaping @Sendable () -> Date = { Date() },
        newID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        (self.api, self.now, self.newID) = (api, now, newID)
    }

    public func preview(_ code: InviteCode) async throws(SignUpError) -> SquadPreview {
        let invite = try await signUp { () throws(APIError) in try await api.invite(code) }
        return SquadPreview(
            code: code, name: invite.name, memberCount: invite.memberCount, isFull: invite.isFull, looks: invite.looks)
    }

    /// Agrees to the copy this build's 你的小队 step shows. Its version moves with that copy, and
    /// the API refuses an older one once the copy changes.
    public func agreeToAI() async throws(SignUpError) {
        try await signUp { () throws(APIError) in try await api.agreeToAI(copyVersion: Self.aiConsentCopyVersion) }
    }

    static let aiConsentCopyVersion = 2

    public func join(_ code: InviteCode) async throws(SignUpError) -> JoinedSquad {
        try await joined(try await signUp { () throws(APIError) in try await api.join(code) })
    }

    public func create(named name: SquadName) async throws(SignUpError) -> JoinedSquad {
        let id = SquadID(newID())
        return try await joined(try await signUp { () throws(APIError) in try await api.createSquad(id, named: name) })
    }

    /// Saves the character on the profile, keeping the rest of it: the profile is saved whole.
    public func save(_ character: NewCharacter) async throws(SignUpError) {
        try await signUp { () throws(APIError) in
            let profile = try await api.me().profile
            _ = try await api.save(
                Profile(
                    timeZone: profile?.timeZone ?? .current, catchphrase: profile?.catchphrase,
                    character: MemberCharacter(
                        nickname: character.nickname,
                        look: CharacterLook(outfit: character.outfit, persona: character.persona))))
        }
    }

    /// Saves the plan for the week today is in, on the member's own clock.
    public func savePlan(_ days: [PlanDay]) async throws(SignUpError) {
        try await signUp { () throws(APIError) in
            let zone = try await api.me().profile?.timeZone ?? .current
            _ = try await api.save(days, weekStart: LocalDay(at: now(), in: zone).weekStart)
        }
    }

    /// The squad as 上场 shows it: the teammates who have made their character, and the squad's
    /// week without the member's own days, which the entrance adds.
    private func joined(_ squad: Squad) async throws(SignUpError) -> JoinedSquad {
        let (member, today) = try await signUp { () throws(APIError) in
            (try await api.me().id, try await api.today(of: squad.id))
        }
        let mine = today.myWeek.week
        return JoinedSquad(
            id: squad.id, name: squad.name,
            teammates: squad.members.compactMap { id in
                guard id != member, let character = today.members.first(where: { $0.member == id })?.character
                else { return nil }
                return Squadmate(
                    id: id, nickname: character.nickname.text, outfit: Outfit(character.look),
                    persona: Persona(character.look))
            },
            weekGoal: max(today.squadWeek.plannedDays - mine.plannedDays, 0),
            weekDone: max(today.squadWeek.trainedDays - mine.trainedDays, 0))
    }

    private func signUp<T>(_ call: () async throws(APIError) -> T) async throws(SignUpError) -> T {
        do {
            return try await call()
        } catch .refused(.inviteCodeUnknown) {
            throw .unknownInvite
        } catch .refused(.squadFull) {
            throw .squadFull
        } catch .refused(.squadLimitReached) {
            throw .tooManySquads
        } catch .refused {
            throw .rejected
        } catch {
            throw .unavailable
        }
    }
}
