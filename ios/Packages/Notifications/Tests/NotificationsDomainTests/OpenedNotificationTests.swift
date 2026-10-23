import Contracts
import Foundation
import NotificationsDomain
import Testing

@Test func theAwardsPushOpensItsSquadsWeek() throws {
    let squad = "6f1c1d0e-4b7a-4c55-9a3e-2d8f7b1e0c42"

    let opened = OpenedNotification(category: "weeklyAwards", event: ["squad": squad, "weekStart": "2026-10-19"])

    #expect(
        opened
            == .weeklyAwards(
                squad: SquadID(try #require(UUID(uuidString: squad))), week: try LocalDay("2026-10-19")))
}

@Test func anyOtherOrUnreadablePushOpensToday() {
    #expect(OpenedNotification(category: "dailyProgress", event: [:]) == .other)
    #expect(
        OpenedNotification(category: "weeklyAwards", event: ["squad": "nope", "weekStart": "2026-10-19"]) == .other)
    #expect(OpenedNotification(category: nil, event: [:]) == .other)
}
