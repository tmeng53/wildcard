import Contracts
import Foundation
import Testing

struct PlaceKeyTests {
    @Test func aMapsPlaceIsKeyedByItsID() throws {
        let place = try Place(
            name: "Equinox Flatiron", appleID: "I6FD7682FD36BB3BE", latitude: 40.74, longitude: -73.99)
        #expect(place.key?.rawValue == "apple:I6FD7682FD36BB3BE")
    }

    @Test func aPlaceWithoutAMapsIDHasNoKey() throws {
        let place = try Place(name: "楼下公园", latitude: 40.74, longitude: -73.99)
        #expect(place.key == nil)
    }

    @Test func keysKeepToTheAPIsPattern() throws {
        let uuid = try #require(UUID(uuidString: "6F1C2B4A-0D3E-4F55-9A21-7C8B9D0E1F23"))
        #expect(PlaceKey(squadPlace: uuid).rawValue == "squad:6f1c2b4a-0d3e-4f55-9a21-7c8b9d0e1f23")
        #expect(PlaceKey(rawValue: "squad:6f1c2b4a-0d3e-4f55-9a21-7c8b9d0e1f23") != nil)
        #expect(PlaceKey(rawValue: "squad:6F1C2B4A-0D3E-4F55-9A21-7C8B9D0E1F23") == nil)
        #expect(PlaceKey(rawValue: "apple:") == nil)
        #expect(PlaceKey(rawValue: "apple:a b") == nil)
        #expect(PlaceKey(rawValue: "at:40.7400,-73.9900:Equinox") == nil)
        #expect(PlaceKey(appleID: String(repeating: "a", count: 201)) == nil)
    }
}
