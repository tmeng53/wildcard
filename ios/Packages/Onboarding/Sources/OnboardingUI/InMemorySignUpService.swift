import AvatarArt
import AvatarDomain
import Contracts
import DesignSystemUI
import Foundation
import OnboardingDomain

/// Sign-up kept in memory, for previews, UI tests and builds before the API client lands. Every
/// invite code finds the sample squad, and a new squad starts with just the member in it.
public actor InMemorySignUpService: SignUpService {
    private let sample: JoinedSquad
    private(set) var character: NewCharacter?
    private(set) var plan: [PlanDay]?
    private(set) var birthday: Birthday?
    private(set) var squad: JoinedSquad?
    private(set) var agreedToAI = false
    private(set) var scene: SceneID?
    /// The sample squad's captain lets members in (入队需要审核): joining asks them.
    private let asksCaptain: Bool
    private(set) var request: JoinRequest?

    /// `character`: one saved before, for a member back in no squad.
    /// A member who made their character before (`character`) was in a squad, so agreed to AI then.
    public init(sample: JoinedSquad, character: NewCharacter? = nil, asksCaptain: Bool = false) {
        self.sample = sample
        self.character = character
        self.asksCaptain = asksCaptain
        agreedToAI = character != nil
    }

    /// The squad the sample member was in before, whose captain removed them.
    public static var formerSquadName: String { String(copyKey: "晨跑搭子", bundle: Bundle.module) }

    /// A calico in the warm-up kit, Tracy, for a member who made their character before.
    public static var sampleCharacter: NewCharacter? {
        guard let nickname = try? Nickname("Tracy") else { return nil }
        return NewCharacter(
            outfit: Outfit(["body": "calico", "cheeks": "rosy", "top": "warmup-tee", "bottom": "warmup-shorts"]),
            persona: .energetic, nickname: nickname)
    }

    /// 周三不练腿俱乐部: four teammates, one of each species but the person, a persona each,
    /// 14 of 22 planned days done this week, as the home screen is reviewed against.
    public static func sampleSquad(character: NewCharacter? = nil, asksCaptain: Bool = false) -> InMemorySignUpService {
        let teammates: [(String, String, Persona)] = [
            ("可可", "calico", .drama), ("阿杰", "shiba", .energetic), ("米娅", "rabbit", .deadpan),
            ("豆豆", "bear", .shy),
        ]
        return InMemorySignUpService(
            sample: JoinedSquad(
                id: SquadID(UUID()),
                name: String(copyKey: "周三不练腿俱乐部", bundle: Bundle.module),
                teammates: teammates.map { name, body, persona in
                    Squadmate(
                        id: MemberID(UUID()), nickname: name,
                        outfit: Outfit(["body": body, "cheeks": "rosy", "top": "warmup-tee", "bottom": "warmup-shorts"]
                        ), persona: persona
                    )
                },
                weekGoal: 3 * teammates.count, weekDone: 9, daysPerMember: 3),
            character: character, asksCaptain: asksCaptain)
    }

    public func preview(_ code: InviteCode) async throws(SignUpError) -> SquadPreview {
        SquadPreview(
            code: code, name: sample.name, memberCount: sample.teammates.count, isFull: false,
            needsApproval: asksCaptain,
            looks: sample.teammates.map { CharacterLook(outfit: $0.outfit, persona: $0.persona) })
    }

    public func agreeToAI() async throws(SignUpError) {
        agreedToAI = true
    }

    public func join(_ code: InviteCode, note: JoinNote?) async throws(SignUpError) -> JoinOutcome {
        guard agreedToAI else { throw .rejected }
        guard asksCaptain else {
            squad = sample
            return .joined(sample)
        }
        let looks = sample.teammates.map { CharacterLook(outfit: $0.outfit, persona: $0.persona) }
        let captain = sample.teammates.first.flatMap { mate in
            (try? Nickname(mate.nickname)).map {
                MemberCharacter(nickname: $0, look: CharacterLook(outfit: mate.outfit, persona: mate.persona))
            }
        }
        let asked = JoinRequest(
            id: request?.id ?? JoinRequestID(UUID()), squad: sample.id, squadName: sample.name, note: note?.text,
            status: .waiting, memberCount: sample.teammates.count, looks: looks, captain: captain)
        request = asked
        return .asked(asked)
    }

    public func joinRequest() async throws(SignUpError) -> JoinRequest? { request }

    public func withdrawJoinRequest() async throws(SignUpError) {
        request = request.map(Self.ended(.over))
    }

    /// The captain answers the waiting request, as on their phone: a yes puts the member in.
    public func answer(approving: Bool) {
        guard let waiting = request, waiting.status == .waiting else { return }
        request = Self.ended(approving ? .approved : .declined)(waiting)
        if approving { squad = sample }
    }

    private static func ended(_ status: JoinRequest.Status) -> @Sendable (JoinRequest) -> JoinRequest {
        { request in
            JoinRequest(
                id: request.id, squad: request.squad, squadName: request.squadName, note: request.note, status: status,
                memberCount: request.memberCount, looks: request.looks, captain: request.captain)
        }
    }

    public func create(
        named name: SquadName, daysPerMember: Int, timeZone: String
    ) async throws(SignUpError) -> JoinedSquad {
        guard agreedToAI, SquadWeeklyGoal.choices.contains(daysPerMember), TimeZone(identifier: timeZone) != nil
        else { throw .rejected }
        let made = JoinedSquad(
            id: SquadID(UUID()), name: name.text, teammates: [], weekGoal: 0, weekDone: 0, daysPerMember: daysPerMember)
        squad = made
        return made
    }

    public func save(_ character: NewCharacter) async throws(SignUpError) {
        self.character = character
    }

    public func save(birthday: Birthday) async throws(SignUpError) {
        self.birthday = birthday
    }

    public func savePlan(_ days: [PlanDay]) async throws(SignUpError) {
        guard days.count == WeeklyPlan.dayCount else { throw .rejected }
        plan = days
    }

    public func pickScene(_ scene: SceneID, for squad: SquadID) async throws(SignUpError) {
        guard squad == self.squad?.id, self.scene == nil || self.scene == scene else { throw .rejected }
        self.scene = scene
    }

    public func character() async throws(SignUpError) -> NewCharacter? { character }

    public func resume(in squad: SquadID) async throws(SignUpError) -> ResumedSignUp {
        guard let joined = self.squad, joined.id == squad else { throw .rejected }
        return ResumedSignUp(squad: joined, character: character)
    }

    /// The sample has no unlock rules: every piece shows.
    public func stock() async -> StreetStock? { nil }
}
