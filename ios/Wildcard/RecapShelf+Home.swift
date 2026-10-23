import CheckInDomain
import Contracts
import DesignSystem
import RecapUI

extension RecapShelf.Squad {
    /// The squad 今天 shows, for its 战报: who is in it and how they look, the reader, and their
    /// day. The story takes the track's colours until each squad picks its own scene.
    init(_ home: Home) {
        self.init(
            id: home.squad.id, today: LocalDay(at: .now, in: home.timeZone),
            cast: StoryCast(
                members: home.today.members.compactMap { StoryMember(member: $0.member, character: $0.character) },
                viewer: home.member, scene: .track))
    }
}
