import Contracts
import Foundation
import PlacesDomain
import Testing

@testable import Backend

// 地点页's adapter against the built API and local Supabase: a place the squad ate at, as a
// teammate reads it, a place nobody tagged, and someone outside the squad.

@Test func aTeammateReadsThePlaceTheSquadAteAt() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let place = try Place(
        name: "Sweetgreen", appleID: "I\(UUID().uuidString.prefix(8))", category: "restaurant",
        latitude: 40.7448, longitude: -73.9881)
    let meal = try checkIn(by: author, to: squad, .healthyMeal(Meal(place: place)))
    _ = try await author.api.save(meal)

    let key = try #require(place.key)
    let detail = try #require(try await APIPlaceSource(api: mate.api).detail(of: key, in: squad))

    #expect(detail.place.name == "Sweetgreen")
    #expect(detail.visits == 1)
    #expect(detail.people == 1)
    #expect(detail.sports == [])
    #expect(detail.meals.healthyMeals == 1)
    #expect(detail.meals.cheatMeals == 0)
    #expect(detail.posts.map(\.id) == [meal.id])
    #expect(detail.posts.map(\.author) == [author.id])
    #expect(detail.posts.map(\.kind) == [.healthyMeal])
}

@Test func aPlaceNobodyTaggedHasNoDetail() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)
    let key = try #require(PlaceKey(appleID: "INeverTagged"))

    #expect(try await APIPlaceSource(api: member.api).detail(of: key, in: squad) == nil)
}

@Test func someoneOutsideTheSquadCantReadItsPlace() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let outsider = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)
    let key = try #require(PlaceKey(appleID: "INeverTagged"))

    await #expect(throws: PlacesError.notInSquad) {
        try await APIPlaceSource(api: outsider.api).detail(of: key, in: squad)
    }
}
