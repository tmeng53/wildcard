import Contracts

/// Who responded to a post and how, with one response a member, such as the emoji on a check-in.
/// A member's response is in place of any they left before.
public struct Responses<Kind: Hashable & Sendable>: Hashable, Sendable {
    /// One member's response.
    public struct Response: Hashable, Sendable {
        public let member: MemberID
        public let kind: Kind
        public let moment: Timestamp

        public init(member: MemberID, kind: Kind, moment: Timestamp) {
            self.member = member
            self.kind = kind
            self.moment = moment
        }
    }

    /// The members who left one kind, oldest first.
    public struct Group: Hashable, Sendable {
        public let kind: Kind
        public let members: [MemberID]
    }

    /// Oldest first, one a member.
    public private(set) var all: [Response]

    /// Keeps each member's latest response.
    public init(_ responses: [Response] = []) {
        var latest: [MemberID: Response] = [:]
        for response in responses where latest[response.member].map({ $0.moment <= response.moment }) ?? true {
            latest[response.member] = response
        }
        all = latest.values.sorted { ($0.moment, $0.member.description) < ($1.moment, $1.member.description) }
    }

    public var isEmpty: Bool { all.isEmpty }

    public func count(of kind: Kind) -> Int { all.count { $0.kind == kind } }

    /// What `member` left, if anything.
    public func kind(of member: MemberID) -> Kind? { all.first { $0.member == member }?.kind }

    /// The kinds anyone left, the most left first; on a tie, the one left first.
    public var groups: [Group] {
        var groups: [Group] = []
        for response in all {
            if let index = groups.firstIndex(where: { $0.kind == response.kind }) {
                groups[index] = Group(kind: response.kind, members: groups[index].members + [response.member])
            } else {
                groups.append(Group(kind: response.kind, members: [response.member]))
            }
        }
        // Stable: ties keep the order they were first left in.
        return groups.enumerated().sorted {
            ($1.element.members.count, $0.offset) < ($0.element.members.count, $1.offset)
        }
        .map(\.element)
    }

    /// The kinds shown at the start of the row: the most left, at most `limit`.
    public func topKinds(_ limit: Int) -> [Kind] { Array(groups.prefix(limit).map(\.kind)) }

    /// The faces at the end of the row: the latest members to respond, newest first.
    public func latestMembers(_ limit: Int) -> [MemberID] {
        Array(all.reversed().prefix(limit).map(\.member))
    }

    /// The same responses with `member`'s set to `kind`, or taken back when nil.
    public func setting(_ kind: Kind?, for member: MemberID, at moment: Timestamp) -> Self {
        var next = self
        next.all.removeAll { $0.member == member }
        if let kind { next.all.append(Response(member: member, kind: kind, moment: moment)) }
        return next
    }
}
