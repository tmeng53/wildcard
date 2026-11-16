import CheckInDomain
import Contracts
import Foundation
import PlacesDomain
import Testing

@testable import Backend

// 自建地点 against the built API and local Supabase, as the place picker uses them: a member adds
// the office canteen, a teammate finds it, tags a meal with it, and its page counts the meal.

@Test func aTeammateFindsAndTagsAPlaceTheSquadAdded() async throws {
    let stack = try LocalStack()
    let adder = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: adder, mate)
    let id = UUID()
    let canteen = try NewSquadPlace(name: "公司食堂", kind: .food, latitude: 40.7466, longitude: -73.9895)

    let added = try await APISquadPlaceSource(api: adder.api).add(canteen, id: id, to: squad)
    // Trying again adds it once.
    let again = try await APISquadPlaceSource(api: adder.api).add(canteen, id: id, to: squad)
    #expect(again == added)
    #expect(added.place.squadPlaceID == id)
    #expect(added.addedBy == adder.id)

    let listed = try await APISquadPlaceSource(api: mate.api).places(in: squad)
    #expect(listed == [added])

    let meal = try checkIn(by: mate, to: squad, .healthyMeal(Meal(place: added.place)))
    _ = try await mate.api.save(meal)

    let key = try #require(added.place.key)
    let detail = try #require(try await APIPlaceSource(api: adder.api).detail(of: key, in: squad))
    #expect(detail.place.name == "公司食堂")
    #expect(detail.place.squadPlaceID == id)
    #expect(detail.posts.map(\.id) == [meal.id])
}

@Test func someoneOutsideTheSquadCantReadOrAddItsPlaces() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let outsider = try await stack.signedInMember()
    let squad = try await stack.squad(of: member)
    let source = APISquadPlaceSource(api: outsider.api)

    await #expect(throws: SquadPlacesError.notInSquad) { try await source.places(in: squad) }
    let gym = try NewSquadPlace(name: "小区健身房", kind: .gym, latitude: 40.74, longitude: -73.99)
    await #expect(throws: SquadPlacesError.notInSquad) { try await source.add(gym, id: UUID(), to: squad) }
}
