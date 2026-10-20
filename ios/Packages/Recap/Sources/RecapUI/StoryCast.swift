#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts
import DesignSystem

/// Someone the story shows: their name and character, from the squad the app already read.
public struct StoryMember: Hashable, Sendable {
    public let id: MemberID
    public let nickname: String
    public let look: Outfit
    public let persona: Persona
    /// The look's species (an `editor.json` species id), whose own moves play on top.
    public let species: String?

    public init(id: MemberID, nickname: String, look: Outfit, persona: Persona, species: String?) {
        self.id = id
        self.nickname = nickname
        self.look = look
        self.persona = persona
        self.species = species
    }
}

/// Who the story is about and who is reading it, and the squad's scene that week: the story
/// takes that scene's colors.
public struct StoryCast: Sendable {
    public let members: [MemberID: StoryMember]
    public let viewer: MemberID
    public let scene: SceneTheme

    public init(members: [StoryMember], viewer: MemberID, scene: SceneTheme) {
        self.members = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.viewer = viewer
        self.scene = scene
    }

    public subscript(id: MemberID) -> StoryMember? { members[id] }

    /// A member who left the squad since the awards shows by id only; nobody else is shown.
    func nickname(of id: MemberID) -> String { members[id]?.nickname ?? "" }
}
#endif
