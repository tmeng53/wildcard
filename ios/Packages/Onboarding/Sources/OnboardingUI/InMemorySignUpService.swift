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
    private(set) var squad: JoinedSquad?
    private(set) var agreedToAI = false
    private(set) var scene: SceneID?

    public init(sample: JoinedSquad) {
        self.sample = sample
    }

    /// 周三不练腿俱乐部: four teammates, one of each species but the person, a persona each,
    /// 14 of 22 planned days done this week, as the home screen is reviewed against.
    public static func sampleSquad() -> InMemorySignUpService {
        let teammates: [(String, String, Persona)] = [
            ("可可", "calico", .drama), ("阿杰", "shiba", .energetic), ("米娅", "rabbit", .deadpan),
            ("豆豆", "bear", .shy),
        ]
        return InMemorySignUpService(
            sample: JoinedSquad(
                id: SquadID(UUID()),
                name: Bundle.module.inAppLanguage.localizedString(forKey: "周三不练腿俱乐部", value: nil, table: nil),
                teammates: teammates.map { name, body, persona in
                    Squadmate(
                        id: MemberID(UUID()), nickname: name,
                        outfit: Outfit(["body": body, "top": "warmup-tee", "bottom": "warmup-shorts"]), persona: persona
                    )
                },
                weekGoal: 22, weekDone: 14))
    }

    public func preview(_ code: InviteCode) async throws(SignUpError) -> SquadPreview {
        SquadPreview(
            code: code, name: sample.name, memberCount: sample.teammates.count, isFull: false,
            looks: sample.teammates.map { CharacterLook(outfit: $0.outfit, persona: $0.persona) })
    }

    public func agreeToAI() async throws(SignUpError) {
        agreedToAI = true
    }

    public func join(_ code: InviteCode) async throws(SignUpError) -> JoinedSquad {
        guard agreedToAI else { throw .rejected }
        squad = sample
        return sample
    }

    public func create(named name: SquadName) async throws(SignUpError) -> JoinedSquad {
        guard agreedToAI else { throw .rejected }
        let made = JoinedSquad(id: SquadID(UUID()), name: name.text, teammates: [], weekGoal: 0, weekDone: 0)
        squad = made
        return made
    }

    public func save(_ character: NewCharacter) async throws(SignUpError) {
        self.character = character
    }

    public func savePlan(_ days: [PlanDay]) async throws(SignUpError) {
        guard days.count == WeeklyPlan.dayCount else { throw .rejected }
        plan = days
    }

    public func pickScene(_ scene: SceneID, for squad: SquadID) async throws(SignUpError) {
        guard squad == self.squad?.id, self.scene == nil || self.scene == scene else { throw .rejected }
        self.scene = scene
    }

    public func resume(in squad: SquadID) async throws(SignUpError) -> ResumedSignUp {
        guard let joined = self.squad, joined.id == squad else { throw .rejected }
        return ResumedSignUp(squad: joined, character: character)
    }
}
