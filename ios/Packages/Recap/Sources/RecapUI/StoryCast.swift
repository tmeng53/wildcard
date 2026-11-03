#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts
import DesignSystem
import RecapDomain

/// Someone the story shows: their name and character as they were that week.
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
/// takes that scene's colors. All of it is the story's own, frozen at the week's awards, so
/// someone who joined later isn't in it and a new look doesn't change it.
public struct StoryCast: Sendable {
    public let members: [MemberID: StoryMember]
    public let viewer: MemberID
    public let scene: SceneTheme

    public init(members: [StoryMember], viewer: MemberID, scene: SceneTheme) {
        self.members = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.viewer = viewer
        self.scene = scene
    }

    /// The squad as the story keeps it; someone who hadn't made their character is left out.
    public init(story: WeekStory, viewer: MemberID) {
        self.init(
            members: story.squadmates.compactMap { StoryMember(member: $0.member, character: $0.character) },
            viewer: viewer, scene: story.scene)
    }

    public subscript(id: MemberID) -> StoryMember? { members[id] }

    /// The one reading.
    public var reader: StoryMember? { members[viewer] }

    /// Someone the story names without a character shows no name.
    func nickname(of id: MemberID) -> String { members[id]?.nickname ?? "" }
}
#endif
