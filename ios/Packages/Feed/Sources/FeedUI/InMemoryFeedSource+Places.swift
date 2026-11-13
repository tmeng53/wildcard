import CheckInDomain
import Contracts
import FeedDomain
import Foundation

// A place's page on the in-memory squad, worked out from its posts as the API does: only posts
// in the squad's 动态 count, and the squad's score is its members' scores averaged to one decimal.
extension InMemoryFeedSource: PlaceBook {
    public func page(of key: PlaceKey, in squad: SquadID) async throws(FeedError) -> PlacePage? {
        let there = posts(at: key, in: squad)
        guard let newest = there.first, let place = newest.checkIn.entry.place else { return nil }
        let scores = (placeScores[key] ?? [:]).filter { characters[$0.key] != nil || $0.key == viewer }.map(\.value)
        let average = scores.isEmpty ? nil : (Double(scores.reduce(0, +)) / Double(scores.count) * 10).rounded() / 10
        return PlacePage(
            key: key, place: place, visits: there.count, people: Set(there.map(\.checkIn.member)).count,
            stars: average, raters: scores.count, myStars: placeScores[key]?[viewer], sports: Self.sports(in: there),
            meals: Self.meals(in: there), posts: there.compactMap(Self.visit))
    }

    public func rate(_ key: PlaceKey, stars: Int) async throws(FeedError) {
        guard PlacePage.scores.contains(stars) else { throw .refused }
        placeScores[key, default: [:]][viewer] = stars
    }

    /// The squad's posts in 动态 tagged with the place, newest first.
    private func posts(at key: PlaceKey, in squad: SquadID) -> [FeedPost] {
        allPosts.filter {
            $0.checkIn.inFeed && $0.checkIn.audience.squads.contains(squad) && $0.checkIn.entry.place?.key == key
        }
        .sorted { $0.checkIn.createdAt > $1.checkIn.createdAt }
    }

    private static func sports(in posts: [FeedPost]) -> [PlacePage.SportCount] {
        var counts: [Activity: Int] = [:]
        var order: [Activity] = []
        for post in posts {
            guard case .trained(let training) = post.checkIn.entry else { continue }
            if counts[training.activity] == nil { order.append(training.activity) }
            counts[training.activity, default: 0] += 1
        }
        return order.map { PlacePage.SportCount(activity: $0, count: counts[$0] ?? 0) }
            .enumerated().sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }.map(\.element)
    }

    private static func meals(in posts: [FeedPost]) -> PlacePage.Meals {
        var healthyMeals = 0, cheatMeals = 0
        var ratings: [MealRating] = []
        for post in posts {
            switch post.checkIn.entry {
            case .healthyMeal(let meal):
                healthyMeals += 1
                ratings += [meal.rating].compactMap(\.self)
            case .cheatMeal(let meal):
                cheatMeals += 1
                ratings += [meal.rating].compactMap(\.self)
            case .trained, .disclaimer: continue
            }
        }
        func average(_ value: (MealRating) -> Double) -> Double? {
            ratings.isEmpty ? nil : (ratings.map(value).reduce(0, +) / Double(ratings.count) * 10).rounded() / 10
        }
        return PlacePage.Meals(
            healthyMeals: healthyMeals, cheatMeals: cheatMeals, healthy: average { Double($0.healthy) },
            tasty: average { Double($0.tasty) }, calorieValue: average(\.calorieValue))
    }

    private static func visit(_ post: FeedPost) -> PlaceVisit? {
        let checkIn = post.checkIn
        let (kind, minutes): (PlaceVisit.Kind, Int?)
        switch checkIn.entry {
        case .trained(let training): (kind, minutes) = (.trained(training.activity), training.minutes?.value)
        case .healthyMeal: (kind, minutes) = (.healthyMeal, nil)
        case .cheatMeal: (kind, minutes) = (.cheatMeal, nil)
        case .disclaimer: return nil
        }
        return PlaceVisit(
            checkIn: checkIn.id, member: checkIn.member, kind: kind, minutes: minutes, day: checkIn.day,
            createdAt: checkIn.createdAt)
    }
}
