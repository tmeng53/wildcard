import Contracts
import FeedDomain
import Foundation
import Testing

@testable import Backend

// A place's page (地点页) against the built API and local Supabase: a teammate's 训练 tagged with
// a gym, then a score for it, as the page reads and gives them.

@Test func aTeammateSeesWhatTheSquadDidAtAPlaceAndScoresIt() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let gym = try Place(
        name: "Equinox Flatiron", appleID: "I6FD7682FD36BB3BE", category: "fitnessCenter", latitude: 40.7411,
        longitude: -73.9897)
    let key = try #require(gym.key)
    let run = try checkIn(
        by: author, to: squad,
        .trained(Training(activity: .sport("run"), minutes: try WorkoutMinutes(30), place: gym)))
    _ = try await author.api.save(run)

    let book = APIFeedSource(api: mate.api)
    let page = try #require(try await book.page(of: key, in: squad))
    #expect(page.place == gym)
    #expect(page.visits == 1)
    #expect(page.people == 1)
    #expect(page.stars == nil)
    #expect(page.myStars == nil)
    #expect(page.sports == [PlacePage.SportCount(activity: .sport("run"), count: 1)])
    #expect(page.meals == .none)
    #expect(page.posts.map(\.checkIn) == [run.id])
    #expect(page.posts.first?.kind == .trained(.sport("run")))
    #expect(page.posts.first?.minutes == 30)
    #expect(page.posts.first?.member == author.id)

    try await book.rate(key, stars: 4)
    try await book.rate(key, stars: 4)
    let rated = try #require(try await book.page(of: key, in: squad))
    #expect(rated.myStars == 4)
    #expect(rated.stars == 4)
    #expect(rated.raters == 1)
}

@Test func aPlaceNobodyPostedFromHasNoPageAndOutsidersAreToldSo() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let outsider = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)
    let key = try #require(PlaceKey.apple("I0000000000000000"))
    #expect(try await APIFeedSource(api: member.api).page(of: key, in: squad) == nil)
    await #expect(throws: FeedError.notInSquad) {
        try await APIFeedSource(api: outsider.api).page(of: key, in: squad)
    }
}
