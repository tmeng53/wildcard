import Contracts
import Foundation
import Testing

private func day(_ text: String) throws -> LocalDay { try LocalDay(text) }
private func monthDay(_ text: String) throws -> CatalogSwitch.MonthDay { try #require(.init(text)) }

@Test func aScheduleRunsOverNewYearBothEndsIncluded() throws {
    let winter = CatalogSwitch(id: "winter", mode: .schedule(start: try monthDay("11-15"), end: try monthDay("03-31")))
    #expect(!winter.isOn(on: try day("2026-11-14")))
    #expect(winter.isOn(on: try day("2026-11-15")))
    #expect(winter.isOn(on: try day("2027-01-01")))
    #expect(winter.isOn(on: try day("2027-03-31")))
    #expect(!winter.isOn(on: try day("2027-04-01")))
}

@Test func aScheduleWithinOneYear() throws {
    let summer = CatalogSwitch(id: "summer", mode: .schedule(start: try monthDay("06-01"), end: try monthDay("08-31")))
    #expect(!summer.isOn(on: try day("2026-05-31")))
    #expect(summer.isOn(on: try day("2026-07-04")))
    #expect(!summer.isOn(on: try day("2026-09-01")))
}

@Test func onAndOffWhateverTheDay() throws {
    #expect(CatalogSwitch(id: "a", mode: .alwaysOn).isOn(on: try day("2026-07-01")))
    #expect(!CatalogSwitch(id: "a", mode: .alwaysOff).isOn(on: try day("2026-07-01")))
}

@Test func aMonthDayIsOnlyMMDD() {
    #expect(CatalogSwitch.MonthDay("13-01") == nil)
    #expect(CatalogSwitch.MonthDay("1-01") == nil)
    #expect(CatalogSwitch.MonthDay("12-1x") == nil)
    #expect(CatalogSwitch.MonthDay("12-31") != nil)
}

@Test func theBoardCountsDaysInNewYorkAndAnUnlistedSwitchIsOff() throws {
    let board = Switchboard()
    board.show([
        CatalogSwitch(id: "betaFreePlan", mode: .alwaysOn),
        CatalogSwitch(id: "dec1", mode: .schedule(start: try monthDay("12-01"), end: try monthDay("12-01"))),
    ])
    #expect(board.isOn(.freePlan, at: Date(timeIntervalSince1970: 0)))
    #expect(!board.isOn(.feedbackReward, at: Date(timeIntervalSince1970: 0)))
    // 2026-12-02 03:00 UTC is still December 1 in New York.
    #expect(board.isOn("dec1", at: Date(timeIntervalSince1970: 1_796_180_400)))
    // 2026-12-02 06:00 UTC is December 2 there.
    #expect(!board.isOn("dec1", at: Date(timeIntervalSince1970: 1_796_191_200)))
}
