import Contracts
import Foundation
import NotificationsDomain
import Testing

@Test func theAwardsPushOpensItsSquadsWeek() throws {
    let squad = "6f1c1d0e-4b7a-4c55-9a3e-2d8f7b1e0c42"

    let opened = OpenedNotification(category: "weeklyAwards", event: ["squad": squad, "weekStart": "2026-10-19"])

    let id = SquadID(try #require(UUID(uuidString: squad)))
    #expect(opened == .open(.recap(squad: id, week: try LocalDay("2026-10-19"))))
}

@Test func theCommentPushOpensItsPost() throws {
    let checkIn = "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59"

    let opened = OpenedNotification(
        category: "comment", event: ["kind": "comment", "checkIn": checkIn, "comment": "x"])

    #expect(opened == .open(.post(CheckInID(try #require(UUID(uuidString: checkIn))))))
}

@Test func theDailyPushOpensTodayWhereItsPatsPlayAgain() {
    #expect(OpenedNotification(category: "dailyProgress", event: [:]) == .open(.pats))
    // A morning note's push opens 今天 on the newest waiting note.
    #expect(OpenedNotification(category: "coachNote", event: ["note": "7"]) == .open(.waitingCoachNote))
}

@Test func aPushOpensWhereItsNoticeInTheBellGoes() throws {
    let squad = SquadID(try #require(UUID(uuidString: "6f1c1d0e-4b7a-4c55-9a3e-2d8f7b1e0c42")))
    let checkIn = CheckInID(try #require(UUID(uuidString: "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59")))
    let week = try LocalDay("2026-10-19")
    let notice = { (squad: SquadID?, subject: Notice.Subject) in
        Notice(id: NoticeID(rawValue: 1), toldAt: .now, squad: squad, subject: subject)
    }

    #expect(
        OpenedNotification(
            category: "weeklyAwards", event: ["squad": squad.description, "weekStart": "2026-10-19"])
            == notice(squad, .weeklyAwards(PushAlert(key: "push.awards"), week: week)).destination.map(
                OpenedNotification.open))
    #expect(
        OpenedNotification(category: "comment", event: ["checkIn": checkIn.description])
            == notice(nil, .comment(PushAlert(key: "push.comment"), checkIn: checkIn)).destination.map(
                OpenedNotification.open))
}

@Test func anyOtherOrUnreadablePushOpensToday() {
    #expect(OpenedNotification(category: "comment", event: ["checkIn": "nope"]) == .other)
    #expect(
        OpenedNotification(category: "weeklyAwards", event: ["squad": "nope", "weekStart": "2026-10-19"]) == .other)
    #expect(OpenedNotification(category: nil, event: [:]) == .other)
}
