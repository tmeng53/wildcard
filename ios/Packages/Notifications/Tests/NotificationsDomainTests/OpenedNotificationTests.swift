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

@Test func theCommentPushOpensItsPost() throws {
    let checkIn = "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59"

    let opened = OpenedNotification(
        category: "comment", event: ["kind": "comment", "checkIn": checkIn, "comment": "x"])

    #expect(opened == .comment(checkIn: CheckInID(try #require(UUID(uuidString: checkIn)))))
}

@Test func anyOtherOrUnreadablePushOpensToday() {
    #expect(OpenedNotification(category: "comment", event: ["checkIn": "nope"]) == .other)
    #expect(
        OpenedNotification(category: "weeklyAwards", event: ["squad": "nope", "weekStart": "2026-10-19"]) == .other)
    #expect(OpenedNotification(category: nil, event: [:]) == .other)
}

@Test func theDailyPushOpensTodayWithItsPats() {
    #expect(OpenedNotification(category: "dailyProgress", event: [:]) == .dailyProgress)
    #expect(OpenedNotification(category: "dailyProgress", event: ["kind": "dailyProgress"]) == .dailyProgress)
}
