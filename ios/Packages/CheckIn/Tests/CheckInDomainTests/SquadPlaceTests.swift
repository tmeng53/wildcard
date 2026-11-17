import CheckInDomain
import Contracts
import Foundation
import Testing

struct SquadPlaceTests {
    private static let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF") ?? UUID()

    @Test func aSquadPlaceIsTaggedByItsOwnKeyAndKindsIcon() throws {
        let place = try SquadPlace(
            id: Self.id, name: " 公司食堂 ", kind: .food, latitude: 40.75, longitude: -73.99, addedBy: nil)
        #expect(place.place.name == "公司食堂")
        #expect(place.place.squadPlaceID == Self.id)
        #expect(place.place.key?.rawValue == "squad:6f9619ff-8b86-d011-b42d-00c04fc964ff")
        #expect(place.place.kind == .food)
        #expect(place.kind.symbol == "fork.knife")
    }

    @Test func eachKindWearsTheIconOfItsCategory() {
        #expect(SquadPlaceKind.food.symbol == "fork.knife")
        #expect(SquadPlaceKind.gym.symbol == "dumbbell.fill")
        #expect(SquadPlaceKind.outdoor.symbol == "tree.fill")
    }

    @Test func aNameTheAPIWouldntTakeIsRefused() {
        #expect(throws: ContractsError.self) {
            try SquadPlace(id: Self.id, name: "  ", kind: .gym, latitude: 0, longitude: 0, addedBy: nil)
        }
    }

    @Test func aNewPlacesPinIsRoundedSoARetryReadsTheSame() throws {
        let new = try NewSquadPlace(
            name: "公司食堂", kind: .food, latitude: 40.746612345678912, longitude: -73.989512345678912)
        #expect(new.latitude == 40.746612)
        #expect(new.longitude == -73.989512)
    }

    @Test func matchesWhatWasTypedIgnoringCase() throws {
        let place = try SquadPlace(
            id: Self.id, name: "WeWork 健身房", kind: .gym, latitude: 0, longitude: 0, addedBy: nil)
        #expect(place.matches("wework"))
        #expect(place.matches("健身"))
        #expect(place.matches(" "))
        #expect(!place.matches("食堂"))
    }

    @Test func aRetryOfTheSamePlaceKeepsItsIdAndAChangedOneGetsANewId() throws {
        var ids = [
            UUID(uuidString: "00000000-0000-0000-0000-00000000000A"),
            UUID(uuidString: "00000000-0000-0000-0000-00000000000B"),
        ].compactMap(\.self).makeIterator()
        let next = { ids.next() ?? UUID() }
        var attempt = SquadPlaceAttempt()
        let first = try NewSquadPlace(name: "公司食堂", kind: .food, latitude: 40.7466, longitude: -73.9895)
        let moved = try NewSquadPlace(name: "公司食堂", kind: .food, latitude: 40.7467, longitude: -73.9895)
        #expect(attempt.id(for: first, making: next).uuidString == "00000000-0000-0000-0000-00000000000A")
        #expect(attempt.id(for: first, making: next).uuidString == "00000000-0000-0000-0000-00000000000A")
        #expect(attempt.id(for: moved, making: next).uuidString == "00000000-0000-0000-0000-00000000000B")
        #expect(attempt.id(for: moved, making: next).uuidString == "00000000-0000-0000-0000-00000000000B")
    }
}
