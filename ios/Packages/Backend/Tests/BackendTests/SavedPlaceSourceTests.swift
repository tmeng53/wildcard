import Contracts
import Foundation
import PlacesDomain
import Testing

@testable import Backend

// 收藏 against the built API, as the place page's bookmark and 我's list use it. What the server
// keeps (the log, the limit) is the saved-places module's own tests'.

@Test func aMemberSavesAPlaceChangesItsNoteAndRemovesIt() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let source = APISavedPlaceSource(api: member.api)
    let gym = try Place(
        name: "Equinox Flatiron", appleID: "I\(UUID().uuidString.prefix(8))", category: "fitnessCenter",
        latitude: 40.74, longitude: -73.99)
    let noodles = try Place(name: "兰州拉面", appleID: "I\(UUID().uuidString.prefix(8))", latitude: 40.71, longitude: -74)

    let first = try await source.save(gym, note: SavedPlaceNote("周四单车课"))
    _ = try await source.save(noodles, note: nil)
    #expect(first.key == gym.key)
    #expect(first.note?.text == "周四单车课")

    // A new note keeps when it was saved; no note clears it.
    let again = try await source.save(gym, note: nil)
    #expect(again.savedAt == first.savedAt)
    #expect(again.note == nil)

    let listed = try await source.list()
    #expect(listed.map(\.place.name) == ["兰州拉面", "Equinox Flatiron"])
    #expect(listed.last?.place == gym)

    try await source.remove(try #require(gym.key))
    // Removing one that isn't saved is fine too.
    try await source.remove(try #require(gym.key))
    #expect(try await source.list().map(\.place.name) == ["兰州拉面"])
}

@Test func aSessionThatIsOverIsSignedOutForSavedPlaces() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    try await member.account.signOut()
    await #expect(throws: SavedPlacesError.signedOut) { try await APISavedPlaceSource(api: member.api).list() }
}
