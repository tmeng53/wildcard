import Testing

@testable import DesignSystem

struct FlipClockTests {
    private let birthday = FlipClock.date(years: 1900...2026)

    @Test func timeOfDayWrapsBothColumns() {
        let clock = FlipClock.timeOfDay
        #expect(clock.turning([23, 30], column: 0, by: 1) == [0, 30])
        #expect(clock.turning([7, 0], column: 1, by: -1) == [7, 59])
        #expect(clock.turning([7, 58], column: 1, by: 3) == [7, 1])
        #expect(clock.turning([7, 0], column: 1, by: -61) == [7, 59])
    }

    @Test func theYearStopsAtItsEnds() {
        #expect(birthday.turning([2026, 1, 1], column: 0, by: 1) == [2026, 1, 1])
        #expect(birthday.turning([1901, 1, 1], column: 0, by: -30) == [1900, 1, 1])
        #expect(birthday.turning([2000, 1, 1], column: 0, by: -4) == [1996, 1, 1])
    }

    @Test func theMonthAndDayWrap() {
        #expect(birthday.turning([2000, 12, 5], column: 1, by: 1) == [2000, 1, 5])
        #expect(birthday.turning([2000, 1, 1], column: 2, by: -1) == [2000, 1, 31])
        #expect(birthday.turning([2000, 4, 30], column: 2, by: 1) == [2000, 4, 1])
    }

    @Test func theDayFollowsTheMonthAndYear() {
        #expect(birthday.turning([2001, 1, 30], column: 1, by: 1) == [2001, 2, 28])
        #expect(birthday.turning([2000, 1, 31], column: 1, by: 1) == [2000, 2, 29])
        #expect(birthday.turning([2000, 2, 29], column: 0, by: 1) == [2001, 2, 28])
        #expect(birthday.turning([2001, 2, 28], column: 2, by: 1) == [2001, 2, 1])
        #expect(birthday.turning([1996, 2, 29], column: 2, by: 1) == [1996, 2, 1])
    }

    @Test func settlingHoldsEveryColumnToItsRange() {
        #expect(birthday.settled([1999, 2, 30]) == [1999, 2, 28])
        #expect(birthday.settled([1800, 13, 0]) == [1900, 12, 1])
        #expect(birthday.settled([]) == [1900, 1, 1])
    }

    @Test func monthLengthsFollowTheGregorianCalendar() {
        #expect(FlipClock.daysIn(month: 2, of: 1900) == 28)
        #expect(FlipClock.daysIn(month: 2, of: 2000) == 29)
        #expect(FlipClock.daysIn(month: 2, of: 2024) == 29)
        #expect(FlipClock.daysIn(month: 9, of: 2024) == 30)
        #expect(FlipClock.daysIn(month: 12, of: 2024) == 31)
    }

    @Test func labelsArePaddedToTheColumnsDigits() {
        #expect(birthday.label(4, column: 1) == "04")
        #expect(birthday.label(18, column: 2) == "18")
        #expect(birthday.label(1996, column: 0) == "1996")
        #expect(FlipClock.timeOfDay.label(0, column: 1) == "00")
    }
}
