import Contracts
import Foundation
import NotificationsDomain
import Testing

@Test func noticesGroupIntoTodayThisWeekAndEarlierOnAWeekFromMonday() {
    // Wednesday 2026-11-04 at 10:00.
    let now = monday.addingTimeInterval((48 + 10) * 3600)
    let notices = [
        notice(1, hoursAfterMonday: -1),  // Sunday night: last week
        notice(2, hoursAfterMonday: 1),  // Monday
        notice(3, hoursAfterMonday: 47),  // Tuesday, 23:00
        notice(4, hoursAfterMonday: 49),  // Wednesday, 1:00
        notice(5, hoursAfterMonday: 57),  // Wednesday, 9:00
    ]
    let sections = NoticeSection.sections(notices.shuffled(), now: now, calendar: utc)
    #expect(sections.map(\.heading) == [.today, .thisWeek, .earlier])
    #expect(sections.map { $0.notices.map(\.id.rawValue) } == [[5, 4], [3, 2], [1]])

    // Nothing today: the group is left out.
    #expect(
        NoticeSection.sections([notice(1, hoursAfterMonday: -1)], now: now, calendar: utc).map(\.heading) == [.earlier])
}

@Test func piecesThatCameToOneStoreTogetherAreOneRow() {
    let now = monday.addingTimeInterval(12 * 3600)
    let piece = { (id: Int, item: String, seconds: Double) in
        Notice(
            id: NoticeID(rawValue: id), toldAt: monday.addingTimeInterval(3600 + seconds), squad: nil,
            subject: .unlocked(.piece, item: item))
    }
    let notices = [
        piece(1, "lap-bib", 0),
        piece(2, "lap-singlet", 1),
        piece(3, "deuce-ball", 2),
        piece(4, "deuce-socks", 2),
        // The same store again, but later: its own arrival.
        piece(5, "lap-spikes", 600),
        notice(6, hoursAfterMonday: 2),
    ]
    let rows = NoticeSection.sections(notices.shuffled(), now: now, calendar: utc).flatMap(\.notices)
    #expect(rows.map(\.id.rawValue) == [6, 5, 4, 2])
}

@Test func aPushLineSplitsIntoATitleAndWhatFollows() {
    let poke = PushAlertWords(PushAlert(key: "push.dailyProgress.poke", args: ["3", "12", "小林"]))
    let parts = poke.parts("%3$@拍了拍你 · 本周小队已练 %1$@/%2$@ 次")
    // The week comes first, as the approved bell design shows it, whatever order the push says it in.
    #expect(parts.title == "本周小队已练 3/12 次")
    #expect(parts.detail == "小林拍了拍你")

    let received = PushAlertWords(key: "push.dailyProgress.received", args: ["3", "12", "2"])
        .parts("本周小队已练 %1$@/%2$@ 次 · 今天 %3$@ 位队友给你打了气")
    #expect(received.title == "本周小队已练 3/12 次")
    #expect(received.detail == "今天 2 位队友给你打了气")

    let plain = PushAlertWords(key: "push.dailyProgress", args: ["3", "12"]).parts("本周小队已练 %1$@/%2$@ 次")
    #expect(plain.title == "本周小队已练 3/12 次")
    #expect(plain.detail == nil)
}

@Test func aCommentOpensThePostAndReadsAsItsPushPutIt() throws {
    let checkIn = CheckInID(try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")))
    let alert = PushAlert(key: "push.comment", args: ["Coco", "这组深蹲太稳了"])
    let comment = Notice(
        id: NoticeID(rawValue: 1), toldAt: monday, squad: nil, subject: .comment(alert, checkIn: checkIn))
    #expect(comment.destination == .post(checkIn))
    let parts = PushAlertWords(alert).parts("%1$@ 评论了你：%2$@")
    #expect(parts.title == "Coco 评论了你：这组深蹲太稳了")
    #expect(parts.detail == nil)
}
