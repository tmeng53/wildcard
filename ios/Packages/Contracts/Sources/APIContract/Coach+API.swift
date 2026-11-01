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
