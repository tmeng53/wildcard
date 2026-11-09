import CheckInDomain
import Contracts
import Foundation

/// The coach's side of the medium widget (教练对你说): the squad's coach, what it says to me today
/// and the day's challenge, which the widget answers and marks done in place.
public struct CoachFace: Hashable, Sendable {
    /// Today's challenge as the widget offers it.
    public struct Challenge: Hashable, Sendable {
        /// The squad and the morning note that set it, by its id, which answering and completing
        /// name.
        public let squad: SquadID
        public let note: String
        /// What to do then how much, as 我的一周 shows it: 「拉伸 20 分钟」.
        public let title: String
        public let step: ChallengeStep

        public init(squad: SquadID, note: String, title: String, step: ChallengeStep) {
            (self.squad, self.note, self.title, self.step) = (squad, note, title, step)
        }
    }

    public let coach: CoachSpeaker
    /// What it says to me: my morning note (便条) while it waits, else the squad's 战术板 line
    /// while its day lasts; nil when it has said nothing yet today.
    public let line: String?
    /// It has a card I haven't seen: its phone's ink dot.
    public let hasNews: Bool
    /// Today's challenge, unless there is none or I let it go.
    public let challenge: Challenge?

    public init(coach: CoachSpeaker, line: String?, hasNews: Bool, challenge: Challenge?) {
        (self.coach, self.line, self.hasNews, self.challenge) = (coach, line, hasNews, challenge)
    }

    /// - Parameters:
    ///   - squad: the squad the coach is with.
    ///   - morningNote: my note from this coach, while it waits; another coach's is left out.
    ///   - moment: now, for whether the 战术板 line's day still lasts.
    public init(
        squad: SquadID, coach: SidelineCoach, morningNote: CoachMemberNote?, challenge: DayChallenge?, hasNews: Bool,
        at moment: Date
    ) {
        self.coach = coach.coach
        line = morningNote.flatMap { $0.coach.id == coach.coach.id ? $0.text : nil } ?? coach.line(at: moment)?.text
        self.hasNews = hasNews
        self.challenge = challenge.flatMap { Self.offer($0, in: squad) }
    }

    /// The challenge as the widget shows it; nil for one I declined, which has nothing left to do.
    private static func offer(_ day: DayChallenge, in squad: SquadID) -> Challenge? {
        let challenge = day.challenge
        let step: ChallengeStep
        switch (challenge.answer, challenge.completedBy) {
        case (_, .some): step = .done
        case (.declined, nil): return nil
        case (.accepted, nil): step = .accepted
        case (nil, nil): step = .open
        }
        let amount = challenge.amount.map { amount in [String(amount), challenge.unit].compactMap(\.self) } ?? []
        return Challenge(
            squad: squad, note: day.note, title: ([challenge.title] + amount).joined(separator: " "), step: step)
    }
}

/// Where today's challenge stands on the coach's side, which picks its button.
public enum ChallengeStep: Hashable, Sendable {
    /// Not answered yet: 接受.
    case open
    /// Accepted and not yet done: 完成.
    case accepted
    /// Done, by me or by the coach from my check-in: 完成了.
    case done
}
