import Contracts
import Foundation
import PlacesDomain
import Synchronization
import Testing

@MainActor
struct SavedPlacesStoreTests {
    private let gym: Place
    private let noodles: Place

    init() throws {
        gym = try Place(
            name: "Equinox Flatiron", appleID: "I1", category: "fitnessCenter", latitude: 40.74, longitude: -73.99)
        noodles = try Place(name: "兰州拉面", appleID: "I2", category: "restaurant", latitude: 40.71, longitude: -74)
    }

    /// Hands out 1000, 2000, … so each new save is newer.
    private static func clock() -> @Sendable () -> Timestamp {
        let ticks = Ticks()
        return { ticks.next() }
    }

    private final class Ticks: Sendable {
        private let count = Mutex<Int64>(0)
        func next() -> Timestamp {
            Timestamp(
                millisecondsSince1970: count.withLock { count in
                    count += 1000
                    return count
                })
        }
    }

    /// A source that refuses every write with `failure`, and reads `places`.
    private actor Refusing: SavedPlaceSource {
        let places: [SavedPlace]
        let failure: SavedPlacesError
        init(places: [SavedPlace], failure: SavedPlacesError) { (self.places, self.failure) = (places, failure) }
        func list() async throws(SavedPlacesError) -> [SavedPlace] {
            if failure == .signedOut { throw failure }
            return places
        }
        func save(_ place: Place, note: SavedPlaceNote?) async throws(SavedPlacesError) -> SavedPlace { throw failure }
        func remove(_ key: PlaceKey) async throws(SavedPlacesError) { throw failure }
    }

    @Test func aNewSaveGoesFirstWithItsNoteTrimmed() async throws {
        let store = SavedPlacesStore(source: InMemorySavedPlaceSource(now: Self.clock()))
        await store.loadIfNeeded()
        #expect(await store.save(gym, note: "") == nil)
        #expect(await store.save(noodles, note: "  加辣  ") == nil)

        #expect(store.places.map(\.place.name) == ["兰州拉面", "Equinox Flatiron"])
        #expect(store.saved(noodles)?.note?.text == "加辣")
        #expect(store.saved(gym)?.note == nil)
    }

    @Test func aNewNoteKeepsThePlaceWhereItWasAndWhenItWasSaved() async throws {
        let store = SavedPlacesStore(source: InMemorySavedPlaceSource(now: Self.clock()))
        _ = await store.save(gym, note: "单车课")
        _ = await store.save(noodles, note: "")
        _ = await store.save(gym, note: "周四单车课")

        #expect(store.places.map(\.place.name) == ["兰州拉面", "Equinox Flatiron"])
        #expect(store.saved(gym)?.note?.text == "周四单车课")
        #expect(store.saved(gym)?.savedAt == Timestamp(millisecondsSince1970: 1000))

        _ = await store.save(gym, note: " ")
        #expect(store.saved(gym)?.note == nil)
    }

    @Test func aRemovedPlaceIsNoLongerSaved() async throws {
        let source = InMemorySavedPlaceSource(now: Self.clock())
        let store = SavedPlacesStore(source: source)
        _ = await store.save(gym, note: "")
        let key = try #require(gym.key)
        #expect(await store.remove(key) == nil)

        #expect(store.saved(gym) == nil)
        #expect(try await source.list().isEmpty)
    }

    @Test func aRemovalTheServerRefusesComesBackWhereItWas() async throws {
        let saved = try [gym, noodles].enumerated().map { index, place in
            SavedPlace(
                key: try #require(place.key), place: place, note: nil,
                savedAt: Timestamp(millisecondsSince1970: Int64(2 - index)))
        }
        let store = SavedPlacesStore(source: Refusing(places: saved, failure: .unavailable))
        await store.load()
        #expect(await store.remove(try #require(gym.key)) == .unavailable)

        #expect(store.places.map(\.place.name) == ["Equinox Flatiron", "兰州拉面"])
    }

    @Test func aSaveTheServerRefusesSaysWhyAndSavesNothing() async throws {
        let store = SavedPlacesStore(source: Refusing(places: [], failure: .full))
        await store.load()
        #expect(await store.save(gym, note: "") == .full)
        #expect(store.saved(gym) == nil)
    }

    @Test func thePhoneKeepsAtMostTheAPIsLimit() async throws {
        let source = InMemorySavedPlaceSource(now: Self.clock())
        for index in 0..<SavedPlace.maxCount {
            let place = try Place(name: "Place \(index)", appleID: "P\(index)", latitude: 0, longitude: 0)
            _ = try await source.save(place, note: nil)
        }
        await #expect(throws: SavedPlacesError.full) { try await source.save(gym, note: nil) }
    }

    @Test func aPlaceWithoutAnAppleIDCanNotBeSaved() async throws {
        let pin = try Place(name: "楼下", latitude: 40, longitude: -73)
        let store = SavedPlacesStore(source: InMemorySavedPlaceSource(now: Self.clock()))
        #expect(await store.save(pin, note: "") == .unavailable)
        #expect(store.places.isEmpty)
    }

    @Test func aSignedOutReadSaysSo() async {
        let store = SavedPlacesStore(source: Refusing(places: [], failure: .signedOut))
        await store.loadIfNeeded()
        #expect(store.phase == .signedOut)
    }

    @Test(arguments: [("", true), ("  ", true), ("周四单车课", true), ("a\nb", false)])
    func whetherANoteCanBeSaved(typed: String, expected: Bool) {
        #expect(SavedPlacesStore.canSave(note: typed) == expected)
    }

    @Test func aNoteLongerThanTheLimitCanNotBeSaved() {
        #expect(SavedPlacesStore.canSave(note: String(repeating: "练", count: 60)))
        #expect(!SavedPlacesStore.canSave(note: String(repeating: "练", count: 61)))
    }
}
