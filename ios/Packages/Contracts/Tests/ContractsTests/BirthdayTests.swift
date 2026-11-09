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

@Test func aDraftOpensOn2000OrTheSavedDayAndKnowsWhenItWasTurned() throws {
    let today = try LocalDay("2026-11-09")
    var draft = BirthdayDraft()
    #expect(draft.values == [2000, 1, 1])
    #expect(!draft.isTouched)
    draft.values = [2000, 1, 1]
    #expect(!draft.isTouched)
    draft.values = [1996, 4, 18]
    #expect(draft.isTouched)
    #expect(draft.birthday(today: today)?.description == "1996-04-18")

    let saved = BirthdayDraft(saved: Birthday(sent: try LocalDay("1988-12-03")))
    #expect(saved.values == [1988, 12, 3])
    #expect(!saved.isTouched)
}

@Test func aDraftAfterTodayIsNoBirthday() throws {
    var draft = BirthdayDraft()
    draft.values = [2026, 11, 10]
    #expect(draft.birthday(today: try LocalDay("2026-11-09")) == nil)
    draft.values = [2026, 2, 30]
    #expect(draft.birthday(today: try LocalDay("2026-11-09")) == nil)
}

@Test func theClockTurnsFrom1900ToThisYear() throws {
    #expect(BirthdayDraft.years(through: try LocalDay("2026-11-09")) == 1900...2026)
}
