import Contracts
import Testing

@Test func aPlaceFromAppleMapsIsKeyedByItsMapsID() throws {
    let place = try Place(name: "Equinox Flatiron", appleID: "I6FD7682FD36BB3BE", latitude: 40.74, longitude: -73.99)
    #expect(place.key?.rawValue == "apple:I6FD7682FD36BB3BE")
}

@Test func aPlaceWithoutAMapsIDHasNoKey() throws {
    let place = try Place(name: "公司食堂", latitude: 40.74, longitude: -73.99)
    #expect(place.key == nil)
}

@Test func onlyKeysTheAPITakesAreKeys() {
    #expect(PlaceKey(rawValue: "apple:I6FD.76_82-F") != nil)
    #expect(PlaceKey(rawValue: "squad:1f0e7c55-3b8a-4c1e-9d0a-2b6f7e8c9d01") != nil)
    #expect(PlaceKey(rawValue: "apple:") == nil)
    #expect(PlaceKey(rawValue: "apple:has space") == nil)
    #expect(PlaceKey(rawValue: "apple:" + String(repeating: "a", count: 201)) == nil)
    #expect(PlaceKey(rawValue: "squad:1F0E7C55-3B8A-4C1E-9D0A-2B6F7E8C9D01") == nil)
    #expect(PlaceKey(rawValue: "squad:not-a-uuid") == nil)
    #expect(PlaceKey(rawValue: "I6FD7682FD36BB3BE") == nil)
}
