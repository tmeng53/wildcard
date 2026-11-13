import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import OnboardingDomain

/// Sign-up over our API: the squad step makes or joins a squad, 角色和昵称 saves the character
/// on the profile, the week step saves the member's typical week and 这周在哪练？ the squad's
/// first scene.
public struct APISignUpService: SignUpService {
    private let api: WildcardAPI
    private let newID: @Sendable () -> UUID

    /// - Parameter newID: the id a new squad is made under, so a retry makes the same squad.
    public init(api: WildcardAPI, newID: @escaping @Sendable () -> UUID = { UUID() }) {
        (self.api, self.newID) = (api, newID)
    }

    public func preview(_ code: InviteCode) async throws(SignUpError) -> SquadPreview {
        let invite = try await signUp { () throws(APIError) in try await api.invite(code) }
        return SquadPreview(
            code: code, name: invite.name, memberCount: invite.memberCount, isFull: invite.isFull,
            needsApproval: invite.needsApproval, looks: invite.looks)
    }

    /// Agrees to the copy this build's 你的小队 step shows. Its version moves with that copy, and
    /// the API refuses an older one once the copy changes.
    public func agreeToAI() async throws(SignUpError) {
        try await signUp { () throws(APIError) in try await api.agreeToAI(copyVersion: Self.aiConsentCopyVersion) }
    }

    static let aiConsentCopyVersion = 3

    public func join(_ code: InviteCode, note: JoinNote?) async throws(SignUpError) -> JoinOutcome {
        switch try await signUp({ () throws(APIError) in try await api.join(code, note: note) }) {
        case .joined(let squad): .joined(try await joined(squad))
        case .asked(let request): .asked(request)
        }
    }

    public func joinRequest() async throws(SignUpError) -> JoinRequest? {
        try await signUp { () throws(APIError) in try await api.joinRequest() }
    }

    public func withdrawJoinRequest() async throws(SignUpError) {
        try await signUp { () throws(APIError) in try await api.withdrawJoinRequest() }
    }

    public func create(
        named name: SquadName, daysPerMember: Int, timeZone: String
    ) async throws(SignUpError) -> JoinedSquad {
        let id = SquadID(newID())
        return try await joined(
            try await signUp { () throws(APIError) in
                try await api.createSquad(id, named: name, daysPerMember: daysPerMember, timeZone: timeZone)
            })
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
                        look: CharacterLook(outfit: character.outfit, persona: character.persona)),
                    jerseyNumber: profile?.jerseyNumber))
        }
    }

    /// Saves the birthday the member picked on 关于你.
    public func save(birthday: Birthday) async throws(SignUpError) {
        try await signUp { () throws(APIError) in try await api.save(birthday) }
    }

    /// Saves the week as the member's 我的每周计划, which this week and every later one follow.
    public func savePlan(_ days: [PlanDay]) async throws(SignUpError) {
        try await signUp { () throws(APIError) in try await api.saveTemplate(days) }
    }

    /// Picks the scene for the week open for picking now, which a squad made today trains on at
    /// once.
    public func pickScene(_ scene: SceneID, for squad: SquadID) async throws(SignUpError) {
        try await signUp { () throws(APIError) in
            let week = try await api.scene(of: squad).week
            _ = try await api.pick(scene, for: squad, week: week)
        }
    }

    /// The squad the member is already in, as joining it returned it, and the character on
    /// their profile.
    public func character() async throws(SignUpError) -> NewCharacter? {
        let member = try await signUp { () throws(APIError) in try await api.me() }
        return member.profile?.character.map { saved in
            NewCharacter(outfit: Outfit(saved.look), persona: Persona(saved.look), nickname: saved.nickname)
        }
    }

    public func resume(in squad: SquadID) async throws(SignUpError) -> ResumedSignUp {
        let found = try await signUp { () throws(APIError) in try await api.squad(squad) }
        return ResumedSignUp(squad: try await joined(found), character: try await character())
    }

    public func stock() async -> StreetStock? {
        try? await api.unlockStanding().stock
    }

    /// The squad as 上场 shows it: the teammates who have made their character, and the squad's
    /// week without the member's own days, which the entrance adds.
    private func joined(_ squad: Squad) async throws(SignUpError) -> JoinedSquad {
        let (member, today) = try await signUp { () throws(APIError) in
            (try await api.me().id, try await api.today(of: squad.id))
        }
        return JoinedSquad(
            id: squad.id, name: squad.name,
            teammates: squad.members.compactMap { id in
                guard id != member, let character = today.members.first(where: { $0.member == id })?.character
                else { return nil }
                return Squadmate(
                    id: id, nickname: character.nickname.text, outfit: Outfit(character.look),
                    persona: Persona(character.look))
            },
            weekGoal: max(today.squadWeek.plannedDays - today.squadDaysPerMember, 0),
            weekDone: today.squadWeek.trainedDays,
            daysPerMember: today.squadDaysPerMember)
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
