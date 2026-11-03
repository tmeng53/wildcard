import Contracts
import Foundation

/// The squad's coach on the home, standing on the sideline (场边), and its 战术板 line.
public struct SidelineCoach: Hashable, Sendable {
    public let coach: CoachSpeaker
    /// The squad's newest 战术板 line, kept only when this coach wrote it: a line from a coach the
    /// squad fired since isn't put in the new one's mouth.
    public let note: CoachNote?

    public init(coach: CoachSpeaker, note: CoachNote?) {
        self.coach = coach
        self.note = note?.coach.id == coach.id ? note : nil
    }

    /// What the coach says on the home at `moment`: its line while the line's day lasts.
    public func line(at moment: Date) -> CoachNote? {
        guard let note, note.isCurrent(at: moment) else { return nil }
        return note
    }
}
