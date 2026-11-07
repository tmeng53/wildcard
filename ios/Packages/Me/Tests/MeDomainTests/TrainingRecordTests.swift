import Contracts
import Foundation
import Testing

@testable import MeDomain

struct TrainingRecordTests {
    private func day(_ text: String) throws -> LocalDay { try LocalDay(text) }

    private func training(_ day: String, _ sport: Sport, minutes: Int?, id: Int) throws -> TrainingDay {
        let uuid = try #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id)))
        return TrainingDay(id: CheckInID(uuid), day: try self.day(day), activity: .sport(sport), minutes: minutes)
    }

    @Test func showsTwentyOneWeeksMondayFirstEndingWithThisWeek() throws {
        // Thursday 2026-11-05.
        let record = TrainingRecord(today: try day("2026-11-05"), trainings: [])
        #expect(record.columns.count == 21)
        #expect(record.columns.allSatisfy { $0.count == 7 })
        #expect(record.columns[0][0].day == (try day("2026-06-15")))
        #expect(TrainingRecord.firstDay(today: try day("2026-11-05")) == (try day("2026-06-15")))
        #expect(record.columns[20][6].day == (try day("2026-11-08")))
        // Friday to Sunday are still ahead.
        #expect(record.columns[20].map(\.isAhead) == [false, false, false, false, true, true, true])
    }

    @Test func shadesADayByItsMinutes() throws {
        let today = try day("2026-11-05")
        let record = TrainingRecord(
            today: today,
            trainings: [
                try training("2026-11-02", "run", minutes: 20, id: 1),
                try training("2026-11-03", "swim", minutes: 45, id: 2),
                try training("2026-11-04", "yoga", minutes: nil, id: 3),
                try training("2026-11-05", "strength", minutes: 60, id: 4),
                try training("2026-11-01", "run", minutes: 10, id: 5),
                try training("2026-11-01", "swim", minutes: 15, id: 6),
                // Before the record: left out.
                try training("2026-01-01", "run", minutes: 90, id: 7),
            ])
        #expect(record.columns[20].map(\.level) == [.light, .steady, .steady, .hard, .none, .none, .none])
        #expect(record.columns[19][6].level == .hard)
        #expect(record.columns.joined().map(\.trainings.count).reduce(0, +) == 6)
    }

    @Test func aDaySaysItsLongestSportAndItsMinutesAddedUp() throws {
        let record = TrainingRecord(
            today: try day("2026-11-05"),
            trainings: [
                try training("2026-11-01", "run", minutes: 10, id: 1),
                try training("2026-11-01", "swim", minutes: 35, id: 2),
                try training("2026-11-01", "yoga", minutes: nil, id: 3),
                try training("2026-11-02", "run", minutes: nil, id: 4),
                try training("2026-11-02", "yoga", minutes: nil, id: 5),
            ])
        let sunday = record.columns[19][6]
        #expect(sunday.main?.activity == .sport("swim"))
        #expect(sunday.minutes == 45)
        #expect(sunday.post == sunday.trainings[1].id)
        // No minutes anywhere: the first made, and no minutes.
        let monday = record.columns[20][0]
        #expect(monday.main?.activity == .sport("run"))
        #expect(monday.minutes == nil)
        #expect(record.columns[20][1].main == nil)
    }

    @Test func namesTheMonthsWhereTheyBegin() throws {
        let record = TrainingRecord(today: try day("2026-11-05"), trainings: [])
        #expect(record.months.map(\.month) == [7, 8, 9, 10, 11])
        // 2026-07-01 is a Wednesday, in the week of 2026-06-29: the third column.
        #expect(record.months.first?.column == 2)
    }
}
