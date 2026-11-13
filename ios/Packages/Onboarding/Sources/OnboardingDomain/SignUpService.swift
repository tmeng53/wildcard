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
    /// Joins the squad by its code, or, for a squad whose captain lets members in (入队需要审核),
    /// asks them, with `note` (备注), withdrawing any request the member had waiting. Safe to repeat.
    func join(_ code: InviteCode, note: JoinNote?) async throws(SignUpError) -> JoinOutcome
    /// The member's newest request to join a squad, waiting or ended; nil if they never asked.
    func joinRequest() async throws(SignUpError) -> JoinRequest?
    /// 撤回申请: withdraws the member's waiting request. Safe to repeat.
    func withdrawJoinRequest() async throws(SignUpError)
    /// Makes a squad with the member in it, its goal, 人均 `daysPerMember` 次, and its 比赛时区,
    /// `timeZone` (an IANA name).
    func create(named name: SquadName, daysPerMember: Int, timeZone: String) async throws(SignUpError) -> JoinedSquad
    /// Saves the character made in 角色和昵称.
    func save(_ character: NewCharacter) async throws(SignUpError)
    /// Saves the birthday the member chose to give on 关于你. Safe to repeat.
    func save(birthday: Birthday) async throws(SignUpError)
    /// Saves the member's typical week, which this week and every later one follow.
    func savePlan(_ days: [PlanDay]) async throws(SignUpError)
    /// Picks where the squad the member made trains, from 这周在哪练？: its first scene, from now
    /// on. Safe to repeat with the same scene.
    func pickScene(_ scene: SceneID, for squad: SquadID) async throws(SignUpError)
    /// The character the member saved, nil before they made one.
    func character() async throws(SignUpError) -> NewCharacter?
    /// The squad the member joined or made in a sign-up the app was closed during, and the
    /// character they saved before it, to carry on from the step after 你的小队.
    func resume(in squad: SquadID) async throws(SignUpError) -> ResumedSignUp
    /// The member's 商店街 as the server works it out, so the character editor offers what is
    /// out for them from the first screen; nil when it can't be read, which keeps the starter
    /// street rather than stops sign-up.
    func stock() async -> StreetStock?
}

/// What 加入小队 did: joined the squad, or asked its captain to let the member in.
public enum JoinOutcome: Hashable, Sendable {
    case joined(JoinedSquad)
    case asked(JoinRequest)
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
    /// The squad's goal this week (小队本周目标) before the member joined, in 训练; the member
    /// adds `daysPerMember` to it.
    public let weekGoal: Int
    /// The 训练 sent to the squad this week (人均 N 次 counts them).
    public let weekDone: Int
    /// The goal its captain set, 人均 N 次.
    public let daysPerMember: Int

    public init(
        id: SquadID, name: String, teammates: [Squadmate], weekGoal: Int, weekDone: Int, daysPerMember: Int = 3
    ) {
        (self.id, self.name, self.teammates) = (id, name, teammates)
        (self.weekGoal, self.weekDone, self.daysPerMember) = (weekGoal, weekDone, daysPerMember)
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
    /// The member is in a squad already: one at a time, so they leave it first.
    case tooManySquads
    /// What was sent was refused: a name or plan the API won't take.
    case rejected
    /// The backend can't be reached or answered with a failure; trying again may work.
    case unavailable
}
