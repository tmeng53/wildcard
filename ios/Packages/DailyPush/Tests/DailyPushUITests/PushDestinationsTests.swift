import DailyPushDomain
import Foundation
import Testing

@testable import DailyPushUI

private let left = Date(timeIntervalSince1970: 1_793_448_000)

private func destinations() throws -> PushDestinations {
    let suite = "PushDestinationsTests-\(UUID().uuidString)"
    return PushDestinations(defaults: try #require(UserDefaults(suiteName: suite)))
}

@Test func theAppTakesWhereThePushAskedToGoOnce() throws {
    let place = try destinations()
    place.leave(.feed, at: left)
    #expect(place.take(at: left.addingTimeInterval(2)) == .feed)
    #expect(place.take(at: left.addingTimeInterval(3)) == nil)
}

@Test func aPlaceLeftLongAgoIsForgotten() throws {
    let place = try destinations()
    place.leave(.checkIn, at: left)
    #expect(place.take(at: left.addingTimeInterval(61)) == nil)
    #expect(place.take(at: left) == nil)
}
