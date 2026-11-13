import Contracts
import Foundation
import Testing

@testable import FeedDomain
@testable import FeedUI

private let viewer = MemberID(UUID())
private let squad = SquadID(UUID())
/// Thursday 2026-10-22, 15:00 in New York.
private let thursday = Date(timeIntervalSince1970: 1_792_695_600)
private let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

private func sample() -> InMemoryFeedSource {
    InMemoryFeedSource.sample(viewer: viewer, squad: squad, now: thursday, zone: newYork)
}

/// The sample's gym: my leg day yesterday, scored 5 and 4 by 阿杰 and Coco; my own score counts.
@Test func theSampleGymsPageCountsMyLegDayAndTakesMyScore() async throws {
    let book = sample()
    let key = try #require(InMemoryFeedSource.sampleGym?.key)
    let page = try #require(try await book.page(of: key, in: squad))
    #expect(page.place.name == "F45 Training Flatiron")
    #expect(page.visits == 1)
    #expect(page.people == 1)
    #expect(page.stars == 4.5)
    #expect(page.raters == 2)
    #expect(page.myStars == nil)
    #expect(page.sports == [PlacePage.SportCount(activity: .sport("strength"), count: 1)])
    #expect(page.posts.map(\.member) == [viewer])
    #expect(page.posts.first?.minutes == 60)

    try await book.rate(key, stars: 4)
    let rated = try #require(try await book.page(of: key, in: squad))
    #expect(rated.myStars == 4)
    #expect(rated.stars == 4.3)
    #expect(rated.raters == 3)
}

/// The sample's restaurant: Mia's rated salad, so its page shows 健康 5, 好吃 4, 卡价比 4.0.
@Test func theSampleRestaurantsPageShowsItsMeal() async throws {
    let key = try #require(InMemoryFeedSource.sampleRestaurant?.key)
    let page = try #require(try await sample().page(of: key, in: squad))
    #expect(page.meals == PlacePage.Meals(healthyMeals: 1, cheatMeals: 0, healthy: 5, tasty: 4, calorieValue: 4))
    #expect(page.sports.isEmpty)
    #expect(page.posts.first?.kind == .healthyMeal)
}

/// A place nobody tagged, another squad's, and a score off the scale.
@Test func anUntaggedPlaceHasNoPageAndAScoreOffTheScaleIsRefused() async throws {
    let book = sample()
    let gym = try #require(InMemoryFeedSource.sampleGym?.key)
    #expect(try await book.page(of: try #require(PlaceKey.apple("I0000")), in: squad) == nil)
    #expect(try await book.page(of: gym, in: SquadID(UUID())) == nil)
    await #expect(throws: FeedError.refused) { try await book.rate(gym, stars: 6) }
}
