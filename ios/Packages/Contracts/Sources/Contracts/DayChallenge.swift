/// The challenge in the member's morning note today (今日挑战), as 今天's 我的一周 shows it once
/// accepted, with 我完成了 until it is done (Tracy, 2026-11-08). Valid on its own day only.
public struct DayChallenge: Hashable, Sendable {
    /// The morning note that set it, by its id.
    public let note: String
    public let day: LocalDay
    public let challenge: CoachPageCard.Challenge

    public init(note: String, day: LocalDay, challenge: CoachPageCard.Challenge) {
        (self.note, self.day, self.challenge) = (note, day, challenge)
    }

    public func completed(by completer: CoachChallengeCompleter) -> DayChallenge {
        DayChallenge(note: note, day: day, challenge: challenge.completed(by: completer))
    }
}
