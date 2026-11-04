import Contracts
import Testing

@testable import FeedDomain

private func backfill(_ counts: String, postedOn posted: String) -> CheckIn {
    let made = checkIn(1, by: coco, on: counts)
    return CheckIn(
        id: made.id, member: made.member, day: made.day, postedDay: day(posted), createdAt: made.createdAt,
        audience: made.audience, entry: made.entry)
}

@Test func aBackfillIsSaidFromTheDayItWasPosted() {
    // 2026-10-22 is a Thursday.
    #expect(BackfillDay(checkIn(1, by: coco, on: "2026-10-22")) == nil)
    #expect(BackfillDay(backfill("2026-10-21", postedOn: "2026-10-22")) == .yesterday)
    #expect(BackfillDay(backfill("2026-10-18", postedOn: "2026-10-22")) == .weekday(7))
    #expect(BackfillDay(backfill("2026-10-16", postedOn: "2026-10-22")) == .weekday(5))
    #expect(BackfillDay(backfill("2026-10-15", postedOn: "2026-10-22")) == .weekdayLastWeek(4))
}

@Test func aBackfillSitsOnTheDayItWasPosted() {
    let posts = [
        FeedPost(checkIn: backfill("2026-10-18", postedOn: "2026-10-22")),
        FeedPost(checkIn: checkIn(2, by: mia, on: "2026-10-21", at: 100)),
    ]
    let sections = FeedSection.sections(posts, today: thursday)
    #expect(sections.map(\.heading) == [.today, .yesterday])
    #expect(sections[0].posts.map(\.id) == [checkInID(1)])
}
