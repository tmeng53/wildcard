import Contracts
import Foundation

/// The squad's coach on the home, standing on the sideline (场边), and its 战术板 line.
public struct SidelineCoach: Hashable, Sendable {
    public let coach: CoachSpeaker
    /// The squad's newest 战术板 line, kept only when this coach wrote it: a line from a coach the
    /// squad fired since isn't put in the new one's mouth.
    public let note: CoachNote?
    /// The letter the coach before it left it when the squad changed coach (交接信), kept only when
    /// it is to this coach.
    public let letter: CoachLetter?

    public init(coach: CoachSpeaker, note: CoachNote?, letter: CoachLetter? = nil) {
        self.coach = coach
        self.note = note?.coach.id == coach.id ? note : nil
        self.letter = letter?.recipient.id == coach.id ? letter : nil
    }

    /// What the coach says on the home at `moment`: its line while the line's day lasts.
    public func line(at moment: Date) -> CoachNote? {
        guard let note, note.isCurrent(at: moment) else { return nil }
        return note
    }
}

/// The squad's coach as last loaded, kept on the device: who stands on its sideline, or nobody.
/// Its line and letter aren't kept; they come with the next load.
public struct SavedCoach: Hashable, Sendable {
    public let squad: SquadID
    public let coach: CoachSpeaker?

    public init(squad: SquadID, coach: CoachSpeaker?) {
        self.squad = squad
        self.coach = coach
    }
}
