import CheckInDomain
import Contracts
import Foundation
import Testing

@Test func aPlacesCategoryPicksItsIcon() throws {
    #expect(PlaceKind.category(fromMaps: "MKPOICategoryFitnessCenter") == "fitnessCenter")
    #expect(PlaceKind.category(fromMaps: "MKPOICategoryRestaurant") == "restaurant")
    #expect(PlaceKind(category: "fitnessCenter").symbol == "dumbbell.fill")
    #expect(PlaceKind(category: "restaurant").symbol == "fork.knife")
    #expect(PlaceKind(category: "park").symbol == "tree.fill")
    #expect(PlaceKind(category: "swimming").symbol == "figure.pool.swim")
    #expect(PlaceKind(category: "stadium").symbol == "sportscourt.fill")
    #expect(PlaceKind(category: "airport").symbol == "mappin")
    #expect(PlaceKind(category: nil).symbol == "mappin")
    let place = try Place(name: "Equinox", category: "fitnessCenter", latitude: 40.7, longitude: -74)
    #expect(place.kind == .gym)
}

@Test func anEditKeepsOrClearsThePlace() throws {
    let place = try Place(name: "Sweetgreen", category: "restaurant", latitude: 40.7, longitude: -74)
    let saved = CheckIn(
        id: CheckInID(UUID()), member: MemberID(UUID()), day: try LocalDay("2026-11-12"),
        createdAt: Timestamp(millisecondsSince1970: 1_794_500_000_000), audience: try Audience([]),
        entry: .healthyMeal(Meal(caption: try Caption("沙拉"), place: place)))
    #expect(saved.entry.place == place)
    let kept = PostEdit(
        original: saved, activity: .sport("run"), minutes: nil, line: "沙拉", photos: [], place: place)
    #expect(try kept.checkIn(uploaded: [:]).entry.place == place)
    let cleared = PostEdit(original: saved, activity: .sport("run"), minutes: nil, line: "沙拉", photos: [])
    #expect(try cleared.checkIn(uploaded: [:]).entry.place == nil)
}
