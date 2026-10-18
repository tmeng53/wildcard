import CheckInDomain
import Contracts
import Testing

@Test func weekStartsOnTheMembersChosenDay() throws {
    // 2026-10-21 is a Wednesday.
    #expect(try Week.containing(day("2026-10-21"), weekStartsOn: .monday).start == day("2026-10-19"))
    #expect(try Week.containing(day("2026-10-21"), weekStartsOn: .sunday).start == day("2026-10-18"))
    #expect(try Week.containing(day("2026-10-21"), weekStartsOn: .wednesday).start == day("2026-10-21"))
    #expect(try Week.containing(day("2026-10-21"), weekStartsOn: .thursday).start == day("2026-10-15"))
}

@Test func weekHasSevenDaysInOrder() throws {
    let week = try Week(startingOn: day("2026-12-28"))
    #expect(
        week.days.map(\.description) == [
            "2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03",
        ])
    #expect(week.contains(day("2027-01-03")))
    #expect(!week.contains(day("2027-01-04")))
}
