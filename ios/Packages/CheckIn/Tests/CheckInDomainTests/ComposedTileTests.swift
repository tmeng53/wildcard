import CheckInDomain
import Contracts
import Foundation
import Testing

@Test func aSavedTrainingOpensWithItsTileWhereItWasPosted() throws {
    let refs = try ["\(myID)/a", "\(myID)/b"].map { try PhotoRef(path: $0) }
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "run-1"),
        startedAt: Timestamp(millisecondsSince1970: 1_792_500_000_000),
        endedAt: Timestamp(millisecondsSince1970: 1_792_501_920_000), summary: WorkoutSummary(durationSec: 1920),
        route: [RoutePoint(lat: 40.78, lon: -73.96), RoutePoint(lat: 40.79, lon: -73.97)], tilePosition: 2)
    let checkIn = CheckIn(
        id: CheckInID(id(501)), member: myID, day: tuesday,
        createdAt: Timestamp(millisecondsSince1970: 1_792_510_000_000), audience: try Audience([squadID]),
        entry: .trained(
            Training(
                activity: .sport("run"), minutes: try WorkoutMinutes(32), photos: try Photos(refs), caption: nil,
                workout: workout)))
    let tiles = ComposedTile.of(checkIn)
    #expect(tiles.map(\.id) == ["saved:\(myID)/a", "workout", "saved:\(myID)/b"])
    #expect(tiles.workoutTilePosition == 2)
    #expect(tiles.photos.map(\.id) == ["saved:\(myID)/a", "saved:\(myID)/b"])
}

@Test func draggingATileMovesItOntoTheOneItIsDroppedOn() throws {
    let first = ComposedTile.photo(.saved(try PhotoRef(path: "\(myID)/a")))
    let second = ComposedTile.photo(.saved(try PhotoRef(path: "\(myID)/b")))
    var tiles: [ComposedTile] = [first, second, .workout(.map)]
    tiles.move("workout", onto: first.id)
    #expect(tiles == [.workout(.map), first, second])
    #expect(tiles.workoutTilePosition == 1)
    tiles.move("workout", onto: second.id)
    #expect(tiles == [first, second, .workout(.map)])
    tiles.move("gone", onto: first.id)
    #expect(tiles == [first, second, .workout(.map)])
    tiles.removeAll { $0 == .workout(.map) }
    #expect(tiles.workoutTilePosition == nil)
}
