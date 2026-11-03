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
    // The squad as it was at that week's awards: its first scene, and nobody, since it was made
    // after them.
    #expect(story.scene == .gym)
    #expect(story.squadmates == [])
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
// awards run. So a frozen story whose titles are late is read from an example of one.
private let lateStory = """
    {"version":1,"status":"pending",
     "squad":{"id":"3f6c1a52-8a0e-4c39-9d43-6b2f3f0b1a11","name":"晨跑五人组"},
     "week":{"from":"2026-10-12","to":"2026-10-18"},
     "scene":"pool",
     "members":[
       {"member":"00000000-0000-0000-0000-000000000001",
        "character":{"nickname":"Coco","look":{"persona":"energetic","variants":{"body":"peach"},"colors":{}}}},
       {"member":"00000000-0000-0000-0000-000000000002"}],
     "podium":{"champion":"00000000-0000-0000-0000-000000000001","sides":["00000000-0000-0000-0000-000000000002"]},
     "myWeek":{"plannedDays":3,"trainedDays":2,"healthyMeals":1,"cheatMeals":0,"reactionsReceived":3,
       "days":[{"day":"2026-10-12","kind":"trained","sport":"run"},{"day":"2026-10-13","kind":"rest"},
         {"day":"2026-10-14","kind":"disclaimer"},{"day":"2026-10-15","kind":"trained","sport":"跳绳"},
         {"day":"2026-10-16","kind":"none"},{"day":"2026-10-17","kind":"none"},{"day":"2026-10-18","kind":"none"}]},
     "hottest":{"checkIn":"8d1c5b7e-2f4a-4e8b-9c0d-1a2b3c4d5e6f","day":"2026-10-15","kind":"trained",
       "sport":"run","caption":"雨里 5 公里",
       "photos":[{"path":"a/b.jpg","url":"https://example.com/b.jpg"}],
       "reactions":[{"emoji":"💪","count":3}]},
     "meals":{"healthy":1,"cheat":2,"eaters":[{"member":"00000000-0000-0000-0000-000000000002","more":"cheat"}]},
     "bestDisclaimer":{"checkIn":"9d1c5b7e-2f4a-4e8b-9c0d-1a2b3c4d5e6f",
       "author":"00000000-0000-0000-0000-000000000002","text":"今天进的是被窝","reactions":2},
     "ending":{"done":4,"plan":6}}
    """

@Test func lateTitlesWaitAndEveryFrozenPageStillPlays() throws {
    let json = lateStory
    let wire = try JSONDecoder().decode(Components.Schemas.WeekStory.self, from: Data(json.utf8))

    let story = try #require(WeekStory(wire))

    let coco = MemberID(try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
    let bea = MemberID(try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")))
    #expect(story.status == .pending)
    #expect(story.squadName == "晨跑五人组")
    #expect(story.week.monday.description == "2026-10-12")
    #expect(story.scene == .pool)
    #expect(
        story.squadmates == [
            Squadmate(
                member: coco,
                character: MemberCharacter(
                    nickname: try Nickname("Coco"),
                    look: CharacterLook(persona: "energetic", variants: ["body": "peach"]))),
            Squadmate(member: bea, character: nil),
        ])
    let podium = try #require(story.podium)
    #expect(podium == Podium(champion: coco, sides: [bea]))
    let hottest = try #require(story.hottest)
    #expect(hottest.sport == "run")
    #expect(hottest.words == "雨里 5 公里")
    #expect(hottest.photos == [try #require(URL(string: "https://example.com/b.jpg"))])
    #expect(hottest.reactions == [ReactionCount(emoji: "💪", count: 3)])
    let myWeek = try #require(story.myWeek)
    #expect(myWeek.plan == 3)
    #expect(myWeek.trainedDays == 2)
    // A sport of the member's own shows just that they trained.
    #expect(
        myWeek.days.map(\.kind) == [.trained("run"), .rest, .disclaimer, .trained(nil), .none, .none, .none])
    let meals = try #require(story.meals)
    #expect(meals == Meals(healthy: 1, cheat: 2, eaters: [.init(member: bea, more: .cheat)]))
    let note = try #require(story.bestDisclaimer)
    #expect(note.author == bea)
    #expect(note.text == "今天进的是被窝")
    let ending = try #require(story.ending)
    #expect(ending == Ending(done: 4, plan: 6))
    #expect(
        story.pages == [
            .podium(podium), .pending, .myWeek(myWeek), .hottest(hottest), .meals(meals), .bestDisclaimer(note),
            .ending(ending),
        ])
}
