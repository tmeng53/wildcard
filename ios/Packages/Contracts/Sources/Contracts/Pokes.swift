/// A member's 拍一拍 in a squad, as the home shows it: whom they patted today (each once a day)
/// and who patted them in the last day, each once, the earliest first.
public struct SquadPokes: Hashable, Sendable {
    public var sent: Set<MemberID>
    public let received: [ReceivedPoke]

    public init(sent: Set<MemberID>, received: [ReceivedPoke]) {
        self.sent = sent
        self.received = received
    }

    public static let none = SquadPokes(sent: [], received: [])
}

/// A pat a teammate gave the member.
public struct ReceivedPoke: Hashable, Sendable {
    public let from: MemberID
    public let patAt: Timestamp

    public init(from: MemberID, patAt: Timestamp) {
        self.from = from
        self.patAt = patAt
    }
}
