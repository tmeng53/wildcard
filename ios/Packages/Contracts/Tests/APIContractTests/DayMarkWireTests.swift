import APIContract
import Contracts
import Testing

/// A day's 训练 on a squadmate's 出赛表, read from their card's week.
struct DayMarkWireTests {
    @Test func everySportTrainedIsReadLatestLast() throws {
        let mark = Components.Schemas.DayMark(
            status: .trained, sport: "tennis",
            sports: [.init(sport: "strength"), .init(sport: "tennis")])
        #expect(try Activity.trained(on: mark) == [.sport("strength"), .sport("tennis")])
    }

    @Test func aDayWithoutATrainingHasNone() throws {
        #expect(try Activity.trained(on: .init(status: .disclaimer)) == nil)
        #expect(try Activity.trained(on: .init(status: .none)) == nil)
    }
}
