import AvatarArt
import AvatarDomain
import Contracts

/// What sign-up asks of the backend. Signing in comes before it, so every call is the signed-in
/// member's. An adapter talks to the API; tests and previews use one in memory.
public protocol SignUpService: Sendable {
    /// The squad an invite code belongs to, to show before joining.
    func preview(_ code: InviteCode) async throws(SignUpError) -> SquadPreview
    /// Records that the member agreed to AI writing for their squad (the weekly awards and the
    /// 请假条), which joining or making one needs. Consent is the account's: asked once, and
    /// withdrawn only by deleting the account. Safe to repeat.
    func agreeToAI() async throws(SignUpError)
    /// Joins the squad by its code. Safe to repeat.
    func join(_ code: InviteCode) async throws(SignUpError) -> JoinedSquad
    /// Makes a squad with the member in it.
    func create(named name: SquadName) async throws(SignUpError) -> JoinedSquad
    /// Saves the character made in 角色和昵称.
    func save(_ character: NewCharacter) async throws(SignUpError)
    /// Saves this week's plan, from 本周目标.
    func savePlan(_ days: [PlanDay]) async throws(SignUpError)
    /// Picks where the squad the member made trains, from 这周在哪练？: its first scene, from now
    /// on. Safe to repeat with the same scene.
    func pickScene(_ scene: SceneID, for squad: SquadID) async throws(SignUpError)
    /// The squad the member joined or made in a sign-up the app was closed during, and the
    /// character they saved before it, to carry on from the step after 你的小队.
    func resume(in squad: SquadID) async throws(SignUpError) -> ResumedSignUp
}

/// What a sign-up the app was closed during had saved: the squad, and the character if it was
/// saved (it always is before the squad, unless the profile couldn't be read).
public struct ResumedSignUp: Hashable, Sendable {
    public let squad: JoinedSquad
    public let character: NewCharacter?

    public init(squad: JoinedSquad, character: NewCharacter?) {
        (self.squad, self.character) = (squad, character)
    }
}

/// The character as 角色和昵称 hands it over.
public struct NewCharacter: Hashable, Sendable {
    public let outfit: Outfit
    public let persona: Persona
    public let nickname: Nickname

    public init(outfit: Outfit, persona: Persona, nickname: Nickname) {
        (self.outfit, self.persona, self.nickname) = (outfit, persona, nickname)
    }
}

/// The squad the member is in once 你的小队 is done: who is there to welcome them at 上场, and
/// the squad's week so far.
public struct JoinedSquad: Hashable, Sendable {
    public let id: SquadID
    public let name: String
    /// Everyone in it but the member, the earliest to join first.
    public let teammates: [Squadmate]
    /// The squad's planned training days this week before the member joined; theirs add to it.
    public let weekGoal: Int
    /// Training days the squad has done this week.
    public let weekDone: Int

    public init(id: SquadID, name: String, teammates: [Squadmate], weekGoal: Int, weekDone: Int) {
        (self.id, self.name, self.teammates) = (id, name, teammates)
        (self.weekGoal, self.weekDone) = (weekGoal, weekDone)
    }
}

/// A teammate as the scene draws them.
public struct Squadmate: Hashable, Sendable, Identifiable {
    public let id: MemberID
    public let nickname: String
    public let outfit: Outfit
    public let persona: Persona

    public init(id: MemberID, nickname: String, outfit: Outfit, persona: Persona) {
        (self.id, self.nickname, self.outfit, self.persona) = (id, nickname, outfit, persona)
    }
}

/// Why a sign-up call failed, as the screen tells the member.
public enum SignUpError: Error, Equatable, Sendable {
    /// No squad has this invite code.
    case unknownInvite
    /// The squad has its 8 members.
    case squadFull
    /// The member is in as many squads as they may be.
    case tooManySquads
    /// What was sent was refused: a name or plan the API won't take.
    case rejected
    /// The backend can't be reached or answered with a failure; trying again may work.
    case unavailable
}
