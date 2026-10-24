import APIContract
import Contracts
import Foundation
import RecapDomain
import Testing

@testable import Backend

// The Sunday 战报 through the app's adapter, against the built API and local Supabase. A week
// two weeks back is past its Sunday 8pm Eastern in any season.

/// The Monday `weeks` weeks from this one, in UTC: negative is the past.
private func monday(weeksFromNow weeks: Int) throws -> LocalDay {
    try day(daysFromThisMonday: 7 * weeks)
}

private func day(daysFromThisMonday days: Int) throws -> LocalDay {
    var utc = Calendar(identifier: .iso8601)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let thisMonday = try #require(utc.dateInterval(of: .weekOfYear, for: Date())).start
    let date = try #require(utc.date(byAdding: .day, value: days, to: thisMonday))
    let parts = utc.dateComponents([.year, .month, .day], from: date)
    return try LocalDay(year: try #require(parts.year), month: try #require(parts.month), day: try #require(parts.day))
}

@Test func aFinishedWeekNobodyCheckedInHasAStoryWithNothingToPlay() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)
    let week = try monday(weeksFromNow: -2)

    let story = try #require(try await APIWeekStoryService(api: member.api).story(squad: squad, week: week))

    #expect(story.squad == squad)
    #expect(story.squadName == "backend tests")
    #expect(story.week.monday == week)
    #expect(story.week.sunday == (try day(daysFromThisMonday: -8)))
    #expect(story.status == .ready)
    #expect(story.titles.isEmpty)
    #expect(story.hottest == nil)
    #expect(story.pages == [])
}

@Test func aWeekThatHasntEndedHasNoStoryYet() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)

    let story = try await APIWeekStoryService(api: member.api).story(squad: squad, week: try monday(weeksFromNow: 1))

    #expect(story == nil)
}

@Test func nudgingTheOrganisersCanBeRepeated() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)
    let service = APIWeekStoryService(api: member.api)
    let week = try monday(weeksFromNow: -2)

    try await service.nudge(squad: squad, week: week)
    try await service.nudge(squad: squad, week: week)
}

@Test func someoneOutsideTheSquadCantReadItsStoryOrNudge() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let outsider = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)
    let service = APIWeekStoryService(api: outsider.api)
    let week = try monday(weeksFromNow: -2)

    await #expect(throws: RecapError.notInSquad) { try await service.story(squad: squad, week: week) }
    await #expect(throws: RecapError.notInSquad) { try await service.nudge(squad: squad, week: week) }
}

// A late week can't be made locally: check-ins can't be dated back to a finished week, and no
// awards run. So the late titles are read from the API's own example of one.
@Test func lateTitlesWaitAndTheHottestCheckInStillPlays() throws {
    let json = """
        {"version":1,"status":"pending",
         "squad":{"id":"3f6c1a52-8a0e-4c39-9d43-6b2f3f0b1a11","name":"晨跑五人组"},
         "week":{"from":"2026-10-12","to":"2026-10-18"},
         "hottest":{"checkIn":"8d1c5b7e-2f4a-4e8b-9c0d-1a2b3c4d5e6f","day":"2026-10-15","kind":"trained",
           "sport":"run","caption":"雨里 5 公里",
           "photos":[{"path":"a/b.jpg","url":"https://example.com/b.jpg"}],
           "reactions":[{"emoji":"💪","count":3}]}}
        """
    let wire = try JSONDecoder().decode(Components.Schemas.WeekStory.self, from: Data(json.utf8))

    let story = try #require(WeekStory(wire))

    #expect(story.status == .pending)
    #expect(story.squadName == "晨跑五人组")
    #expect(story.week.monday.description == "2026-10-12")
    let hottest = try #require(story.hottest)
    #expect(hottest.sport == "run")
    #expect(hottest.words == "雨里 5 公里")
    #expect(hottest.photos == [try #require(URL(string: "https://example.com/b.jpg"))])
    #expect(hottest.reactions == [ReactionCount(emoji: "💪", count: 3)])
    #expect(story.pages == [.pending, .hottest(hottest)])
}
