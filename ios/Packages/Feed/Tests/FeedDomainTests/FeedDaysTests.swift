import Contracts
import Testing

@testable import FeedDomain

// 2026-10-22 is a Thursday; its week starts Monday 2026-10-19.
let thursday = day("2026-10-22")

@Test func headingsNameTodayYesterdayThisWeeksDaysThenDates() {
    #expect(DayHeading(day("2026-10-22"), today: thursday) == .today)
    #expect(DayHeading(day("2026-10-23"), today: thursday) == .today)
    #expect(DayHeading(day("2026-10-21"), today: thursday) == .yesterday)
    #expect(DayHeading(day("2026-10-20"), today: thursday) == .weekday(2))
    #expect(DayHeading(day("2026-10-19"), today: thursday) == .weekday(1))
    #expect(DayHeading(day("2026-10-18"), today: thursday) == .date(day("2026-10-18")))
}

@Test func onMondayYesterdayIsLastWeeksSunday() {
    #expect(DayHeading(day("2026-10-18"), today: day("2026-10-19")) == .yesterday)
    #expect(DayHeading(day("2026-10-17"), today: day("2026-10-19")) == .date(day("2026-10-17")))
}

@Test func sectionsRunNewestDayFirstAndNewestPostFirst() {
    let posts = [
        FeedPost(checkIn: checkIn(1, by: coco, on: "2026-10-21", at: 100)),
        FeedPost(checkIn: checkIn(2, by: mia, on: "2026-10-22", at: 200)),
        FeedPost(checkIn: checkIn(3, by: jay, on: "2026-10-22", at: 300)),
    ]
    let sections = FeedSection.sections(posts, today: thursday)
    #expect(sections.map(\.heading) == [.today, .yesterday])
    #expect(sections[0].posts.map(\.id) == [checkInID(3), checkInID(2)])
    #expect(sections[1].posts.map(\.id) == [checkInID(1)])
}

@Test func aSlipItsAuthorTrainedAfterIsExcusedAtTheirFirstTraining() {
    let slip = FeedPost(checkIn: checkIn(1, by: mia, on: "2026-10-22", at: 100, disclaimer: true))
    let posts = [
        slip,
        FeedPost(checkIn: checkIn(2, by: mia, on: "2026-10-22", at: 500)),
        FeedPost(checkIn: checkIn(3, by: mia, on: "2026-10-22", at: 300)),
        FeedPost(checkIn: checkIn(4, by: jay, on: "2026-10-22", at: 200)),
    ]
    let today = FeedSection.sections(posts, today: thursday)[0]
    #expect(today.excused(slip) == at(300))
    // A 练了 is never excused, and a slip whose author didn't train stays as it is.
    #expect(today.excused(posts[1]) == nil)
    let jaysSlip = FeedPost(checkIn: checkIn(5, by: jay, on: "2026-10-21", at: 100, disclaimer: true))
    #expect(FeedSection.sections([jaysSlip], today: thursday)[0].excused(jaysSlip) == nil)
}

@Test func theLatestRangeIsAWeekReachingADayAheadThenGoesBackAWeekAtATime() {
    let latest = FeedRange.latest(today: thursday)
    #expect(latest == FeedRange(first: day("2026-10-16"), last: day("2026-10-23")))
    #expect(latest.earlier == FeedRange(first: day("2026-10-09"), last: day("2026-10-15")))
}
