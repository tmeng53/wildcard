import Contracts

extension TrainingDay {
    /// One 练了 on the member's training record, as `GET /me/trainings` sends it.
    public init(_ wire: Components.Schemas.TrainingDay) throws(ContractsError) {
        self.init(
            id: try CheckInID(wire: wire.id), day: try LocalDay(wire.day),
            activity: try Activity(sport: wire.sport, customSport: wire.customSport), minutes: wire.minutes)
    }
}
