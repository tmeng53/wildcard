import Contracts
import DesignSystem
import Foundation
import PlacesDomain
import Testing

struct PlaceNumbersTests {
    private let gym: Place
    private let salad: Place
    private let park: Place

    init() throws {
        gym = try Place(
            name: "Equinox Flatiron", appleID: "I1", category: "fitnessCenter", latitude: 40.74, longitude: -73.99)
        salad = try Place(name: "Sweetgreen", appleID: "I2", category: "restaurant", latitude: 40.74, longitude: -73.99)
        park = try Place(name: "Madison Square Park", appleID: "I3", latitude: 40.74, longitude: -73.98)
    }

    private static func detail(
        _ place: Place, sports: [SportCount] = [], meals: MealTally = .none, stars: Double? = nil
    ) -> PlaceDetail {
        PlaceDetail(place: place, visits: 7, people: 3, stars: stars, sports: sports, meals: meals, posts: [])
    }

    @Test func aGymTheSquadNeverTaggedShowsAnEmptyCard() {
        let numbers = PlaceNumbers(kind: gym.kind, detail: nil)
        #expect(numbers.face == .training)
        #expect(numbers.cells == [.squadScore(nil), .visits(0), .people(0)])
        #expect(numbers.rows.isEmpty)
    }

    @Test func aRestaurantTheSquadNeverTaggedShowsHealthyTastyAndVisits() {
        let numbers = PlaceNumbers(kind: salad.kind, detail: nil)
        #expect(numbers.face == .eating)
        #expect(numbers.cells == [.healthy(nil), .tasty(nil), .visits(0)])
    }

    @Test func aGymShowsItsScoreAndItsSportsAgainstTheMostTrained() {
        let detail = Self.detail(
            gym, sports: [SportCount(.sport("cycling"), count: 4), SportCount(.sport("hiit"), count: 1)],
            stars: 4.3)
        let numbers = PlaceNumbers(kind: gym.kind, detail: detail)
        #expect(numbers.cells == [.squadScore(4.3), .visits(7), .people(3)])
        #expect(
            numbers.rows == [
                .sport(.sport("cycling"), count: 4, fraction: 1), .sport(.sport("hiit"), count: 1, fraction: 0.25),
            ])
    }

    @Test func aRestaurantShowsItsMealsAndTheirScores() {
        let meals = MealTally(healthyMeals: 6, cheatMeals: 0, healthy: 4.6, tasty: 4.2, calorieValue: 3.9)
        let numbers = PlaceNumbers(kind: salad.kind, detail: Self.detail(salad, meals: meals))
        #expect(numbers.cells == [.healthy(4.6), .tasty(4.2), .calorieValue(3.9), .visits(7)])
        #expect(numbers.rows == [.healthyMeals(count: 6, fraction: 1)])
    }

    @Test func aPlaceWhereTheSquadOnlyAteShowsItsMeals() {
        let meals = MealTally(healthyMeals: 1, cheatMeals: 2)
        let numbers = PlaceNumbers(kind: park.kind, detail: Self.detail(park, meals: meals))
        #expect(numbers.face == .eating)
        #expect(numbers.rows == [.healthyMeals(count: 1, fraction: 0.5), .cheatMeals(count: 2, fraction: 1)])
    }

    @Test func scoresReadAsWholeStarsOrOneDecimal() {
        #expect(ScoreText.average(4.25) == "4.3")
        #expect(ScoreText.average(4) == "4.0")
        #expect(ScoreText.average(nil) == "—")
        #expect(ScoreText.visit(.stars(5)) == "5")
        #expect(ScoreText.visit(.calorieValue(2.36)) == "2.4")
    }

    @Test func mapsFactsReadAsTheCapsulesSayThem() throws {
        let facts = PlaceFacts(phone: "(212) 780-9300", website: URL(string: "https://www.equinox.com/clubs/flatiron"))
        #expect(facts.websiteName == "equinox.com")
        #expect(facts.phoneURL?.absoluteString == "tel:2127809300")
        #expect(PlaceFacts(phone: "+1 646-449-8884").phoneURL?.absoluteString == "tel:+16464498884")
        #expect(PlaceFacts().phoneURL == nil)
    }

    @Test func mapsOpensAPlaceByItsIDElseByItsNameAndSpot() throws {
        #expect(gym.mapsLink?.absoluteString == "https://maps.apple.com/place?place-id=I1")
        let lot = try Place(name: "楼下", latitude: 40.5, longitude: -73.5)
        #expect(
            lot.mapsLink?.absoluteString
                == "https://maps.apple.com/place?name=%E6%A5%BC%E4%B8%8B&coordinate=40.5,-73.5")
    }
}
