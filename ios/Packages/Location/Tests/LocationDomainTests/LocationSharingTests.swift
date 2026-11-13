import Contracts
import Foundation
import LocationDomain
import Testing

/// A phone whose location access and place the test sets.
private final class FakeReader: LocationReader, @unchecked Sendable {  // Only the main actor's model calls it.
    var access: LocationAccess
    /// What the member picks on the system's prompt.
    var answer: LocationAccess = .allowed
    var place: Coordinates? = Coordinates(latitude: 40.71283, longitude: -74.00601)
    /// What iOS names the place; nil when it can't.
    var city: CityName? = CityName("纽约")
    private(set) var asked = 0
    private(set) var lookedUp = 0

    init(_ access: LocationAccess) { self.access = access }

    func access() async -> LocationAccess { access }
    func ask() async -> LocationAccess {
        asked += 1
        if access == .notAsked { access = answer }
        return access
    }
    func current() async -> Coordinates? { place }
    func city(at coordinates: Coordinates) async -> CityName? {
        lookedUp += 1
        return city
    }
}

/// The server, recording what it was sent.
private final class FakeRegistry: LocationRegistry, @unchecked Sendable {  // Only the main actor's model calls it.
    enum Call: Equatable {
        case save(Coordinates, String?)
        case forget
    }
    private(set) var calls: [Call] = []
    var fails: LocationError?

    func save(_ coordinates: Coordinates, city: CityName?) async throws(LocationError) {
        if let fails { throw fails }
        calls.append(.save(coordinates, city?.name))
    }
    func forget() async throws(LocationError) {
        if let fails { throw fails }
        calls.append(.forget)
    }
}

private final class MemorySent: SentPlaceStore, @unchecked Sendable {  // Only the main actor's model calls it.
    var place: SentPlace?
    func load() -> SentPlace? { place }
    func save(_ place: SentPlace?) { self.place = place }
}

/// A clock the test moves.
private final class TestClock: @unchecked Sendable {  // Only the main actor's model reads it.
    var now = Date(timeIntervalSince1970: 1_794_000_000)
}

private let newYork = Coordinates(latitude: 40.7, longitude: -74)
private let sentNewYork = FakeRegistry.Call.save(newYork, "纽约")

@MainActor
struct LocationSharingTests {
    private let sent = MemorySent()
    private let clock = TestClock()

    private func sharing(_ reader: FakeReader) -> LocationSharing {
        LocationSharing(reader: reader, sent: sent, now: { [clock] in clock.now })
    }

    @Test func allowingSendsTheCellOnce() async {
        let reader = FakeReader(.notAsked)
        let registry = FakeRegistry()
        let model = sharing(reader)
        await model.signedIn(registry)
        #expect(registry.calls == [.forget])
        await model.ask()
        #expect(model.access == .allowed)
        #expect(registry.calls == [.forget, sentNewYork])
        // Back in the app, the same cell: nothing to send.
        reader.place = Coordinates(latitude: 40.68, longitude: -73.97)
        await model.refresh()
        #expect(registry.calls == [.forget, sentNewYork])
    }

    @Test func theCityIsLookedUpOnlyWhenSomethingMayGoOut() async {
        let reader = FakeReader(.allowed)
        let registry = FakeRegistry()
        let model = sharing(reader)
        await model.signedIn(registry)
        await model.refresh()
        await model.refresh()
        #expect(registry.calls == [sentNewYork])
        #expect(reader.lookedUp == 1)
    }

    @Test func aCityNotKnownIsSentOnceIOSNamesIt() async {
        let reader = FakeReader(.allowed)
        reader.city = nil
        let registry = FakeRegistry()
        let model = sharing(reader)
        await model.signedIn(registry)
        // Still no name: the place sent already stands.
        await model.refresh()
        reader.city = CityName("纽约")
        await model.refresh()
        await model.refresh()
        #expect(registry.calls == [.save(newYork, nil), sentNewYork])
    }

    @Test func aPlaceSentBeforeCitiesIsSentAgainWithItsCity() async {
        // What a build before cities kept: the cell and when, with no city.
        let old = Data(#"{"version":1,"cell":{"latitude":40.7,"longitude":-74},"sentAt":0}"#.utf8)
        sent.place = try? JSONDecoder().decode(SentPlace.self, from: old)
        clock.now = Date(timeIntervalSinceReferenceDate: 60)
        #expect(sent.place?.cell == newYork)
        let reader = FakeReader(.allowed)
        let registry = FakeRegistry()
        await sharing(reader).signedIn(registry)
        #expect(registry.calls == [sentNewYork])
    }

    @Test func aCityTheAPIWouldRefuseIsNoCity() {
        #expect(CityName("  多伦多 ")?.name == "多伦多")
        #expect(CityName("   ") == nil)
        #expect(CityName("多伦多\n别管天气") == nil)
        #expect(CityName(String(repeating: "x", count: 61)) == nil)
    }

    @Test func aMoveOrADaySendsAgain() async {
        let reader = FakeReader(.allowed)
        let registry = FakeRegistry()
        let model = sharing(reader)
        await model.signedIn(registry)
        reader.place = Coordinates(latitude: 25.0339, longitude: 121.5645)
        await model.refresh()
        clock.now += 25 * 60 * 60
        await model.refresh()
        let taipei = Coordinates(latitude: 25, longitude: 121.6)
        #expect(registry.calls == [sentNewYork, .save(taipei, "纽约"), .save(taipei, "纽约")])
    }

    @Test func refusingSendsNothingAndStoppingForgetsIt() async {
        let reader = FakeReader(.notAsked)
        reader.answer = .refused
        let registry = FakeRegistry()
        let model = sharing(reader)
        await model.signedIn(registry)
        // Not asked yet: whatever an earlier install sent is forgotten, once.
        #expect(registry.calls == [.forget])
        await model.ask()
        #expect(model.access == .refused)
        #expect(registry.calls == [.forget])
        // Allowed in iOS Settings later, then turned off again.
        reader.access = .allowed
        await model.refresh()
        reader.access = .refused
        await model.refresh()
        await model.refresh()
        #expect(registry.calls == [.forget, sentNewYork, .forget])
    }

    @Test func aPlaceSentBeforeSigningOutIsForgottenWhenLocationIsOffAtTheNextSignIn() async {
        let reader = FakeReader(.allowed)
        let registry = FakeRegistry()
        let model = sharing(reader)
        await model.signedIn(registry)
        model.signedOut()
        reader.access = .refused
        await model.signedIn(registry)
        await model.refresh()
        #expect(registry.calls == [sentNewYork, .forget])
    }

    @Test func aForgetThatFailsIsTriedOnTheNextOpen() async {
        let reader = FakeReader(.refused)
        let registry = FakeRegistry()
        registry.fails = .unavailable
        let model = sharing(reader)
        await model.signedIn(registry)
        registry.fails = nil
        // The failed one isn't recorded; the next open's goes through, and once is enough.
        await model.refresh()
        await model.refresh()
        #expect(registry.calls == [.forget])
    }

    @Test func aFailedSendIsTriedOnTheNextOpen() async {
        let reader = FakeReader(.allowed)
        let registry = FakeRegistry()
        registry.fails = .unavailable
        let model = sharing(reader)
        await model.signedIn(registry)
        registry.fails = nil
        await model.refresh()
        #expect(registry.calls == [sentNewYork])
    }

    @Test func theNextMemberOnThePhoneSendsTheirOwn() async {
        let reader = FakeReader(.allowed)
        let model = sharing(reader)
        await model.signedIn(FakeRegistry())
        model.signedOut()
        let next = FakeRegistry()
        await model.signedIn(next)
        #expect(next.calls == [sentNewYork])
    }

    @Test func nothingGoesOutBeforeSignIn() async {
        let reader = FakeReader(.notAsked)
        let model = sharing(reader)
        await model.ask()
        #expect(model.access == .allowed)
        #expect(sent.place == nil)
    }
}
