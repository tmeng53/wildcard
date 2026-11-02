import Contracts

/// What changed in the member's squad between two homes, for the home to tell once: who joined
/// since, and whether the member was made captain. Leaving says nothing.
public struct SquadNews: Equatable, Sendable {
    /// Teammates in the later home who weren't in the earlier one, in the squad's order.
    public var joined: [MemberID]
    /// The captaincy came to the member.
    public var madeCaptain: Bool

    public init(joined: [MemberID] = [], madeCaptain: Bool = false) {
        self.joined = joined
        self.madeCaptain = madeCaptain
    }

    /// Nothing to tell when there was no earlier home, or it was another squad's.
    public init(from earlier: Home?, to later: Home) {
        guard let earlier, earlier.squad.id == later.squad.id, earlier.member == later.member else {
            self.init()
            return
        }
        self.init(
            joined: later.squad.members.filter { $0 != later.member && !earlier.squad.members.contains($0) },
            madeCaptain: later.squad.captain == later.member && earlier.squad.captain != later.member)
    }

    public var isEmpty: Bool { joined.isEmpty && !madeCaptain }

    /// This news, and then `later`'s, as one: told together if neither was told yet.
    public func adding(_ later: SquadNews) -> SquadNews {
        SquadNews(
            joined: joined + later.joined.filter { !joined.contains($0) },
            madeCaptain: madeCaptain || later.madeCaptain)
    }
}
