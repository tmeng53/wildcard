import Contracts
import Testing

@Test func aBirthdayRunsFrom1900ToToday() throws {
    let today = try LocalDay("2026-11-09")
    #expect(try Birthday(LocalDay("1900-01-01"), today: today).description == "1900-01-01")
    #expect(try Birthday(LocalDay("2026-11-09"), today: today).description == "2026-11-09")
    #expect(throws: ContractsError.birthdayOutOfRange("2026-11-10")) {
        try Birthday(LocalDay("2026-11-10"), today: today)
    }
}

@Test func ageCountsWholeYears() throws {
    let birthday = Birthday(sent: try LocalDay("1996-04-18"))
    #expect(birthday.age(on: try LocalDay("2026-04-17")) == 29)
    #expect(birthday.age(on: try LocalDay("2026-04-18")) == 30)
    #expect(Birthday(sent: try LocalDay("2000-02-29")).age(on: try LocalDay("2025-02-28")) == 24)
    #expect(Birthday(sent: try LocalDay("2000-02-29")).age(on: try LocalDay("2025-03-01")) == 25)
}
