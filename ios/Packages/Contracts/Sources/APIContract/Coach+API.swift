import Contracts
import Foundation

// Reading coaches from the API's wire types.

extension Coach {
    public init(_ wire: Components.Schemas.CoachCard) throws(ContractsError) {
        guard let id = CoachID(rawValue: wire.id) else { throw .invalidCoachID(wire.id) }
        self.init(
            id: id, name: wire.name, title: wire.title, catchphrase: wire.catchphrase, background: wire.background,
            yearsCoaching: wire.yearsCoaching, experience: wire.experience, style: wire.style, tags: wire.tags,
            pay: wire.pay)
    }
}

extension SquadCoach {
    /// A coach without its hire time, or a time without a coach, reads as no coach.
    public init(_ wire: Components.Schemas.SquadCoach) throws(ContractsError) {
        let hire: Hire? =
            if let card = wire.coach?.value1, let since = wire.since {
                Hire(coach: try Coach(card), since: since)
            } else { nil }
        self.init(hire: hire, canHire: wire.canHire)
    }
}

extension CoachID {
    /// The body of `PUT /squads/{squadId}/coach`.
    public var hire: Components.Schemas.CoachHire { .init(version: ._1, coach: rawValue) }
}

extension CoachSpeaker {
    public init(_ wire: Components.Schemas.CoachSpeaker) throws(ContractsError) {
        guard let id = CoachID(rawValue: wire.id) else { throw .invalidCoachID(wire.id) }
        self.init(id: id, name: wire.name)
    }
}

extension CoachNote {
    public init(_ wire: Components.Schemas.CoachNote) throws(ContractsError) {
        self.init(day: try LocalDay(wire.day), text: wire.text, coach: try CoachSpeaker(wire.coach), writtenAt: wire.at)
    }
}

extension CoachReply {
    /// An emoji the app can't read drops the emoji, not the line.
    public init(_ wire: Components.Schemas.CoachReply) throws(ContractsError) {
        self.init(
            checkIn: try CheckInID(wire: wire.checkInId), coach: try CoachSpeaker(wire.coach.value1),
            text: wire.text, emoji: wire.emoji.flatMap { try? Emoji($0) }, writtenAt: wire.at)
    }
}

extension CoachAnswer {
    public init(_ wire: Components.Schemas.CoachAnswer) throws(ContractsError) {
        self.init(
            checkIn: try CheckInID(wire: wire.checkInId), comment: try CommentID(wire: wire.commentId),
            coach: try CoachSpeaker(wire.coach.value1), text: wire.text, writtenAt: wire.at)
    }
}

extension CoachActivity {
    public init(_ wire: Components.Schemas.CoachActivity) throws(ContractsError) {
        self.init(
            note: try wire.note.map { note throws(ContractsError) in try CoachNote(note) },
            replies: try wire.replies.map { reply throws(ContractsError) in try CoachReply(reply) },
            answers: try wire.answers.map { answer throws(ContractsError) in try CoachAnswer(answer) })
    }
}
