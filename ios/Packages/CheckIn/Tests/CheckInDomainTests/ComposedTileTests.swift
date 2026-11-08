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
    #expect(tiles.map(\.id) == ["saved:\(myID)/a", "workout.map", "saved:\(myID)/b"])
    #expect(tiles.workoutTilePositions == [.map: 2])
    #expect(tiles.photos.map(\.id) == ["saved:\(myID)/a", "saved:\(myID)/b"])
}

@Test func draggingATileMovesItOntoTheOneItIsDroppedOn() throws {
    let first = ComposedTile.photo(.saved(try PhotoRef(path: "\(myID)/a")))
    let second = ComposedTile.photo(.saved(try PhotoRef(path: "\(myID)/b")))
    var tiles: [ComposedTile] = [first, second, .workout(.map)]
    tiles.move("workout.map", onto: first.id)
    #expect(tiles == [.workout(.map), first, second])
    #expect(tiles.workoutTilePositions == [.map: 1])
    tiles.move("workout.map", onto: second.id)
    #expect(tiles == [first, second, .workout(.map)])
    tiles.move("gone", onto: first.id)
    #expect(tiles == [first, second, .workout(.map)])
    tiles.removeAll { $0 == .workout(.map) }
    #expect(tiles.workoutTilePositions.isEmpty)
    tiles.insert(.workout(.chart), at: 1)
    tiles.append(.workout(.map))
    #expect(tiles.workoutTilePositions == [.chart: 2, .map: 4])
}

@Test func aPostWrittenOnThePhoneOpensWithItsTileWhereItWasPlaced() {
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "run-2"),
        startedAt: Timestamp(millisecondsSince1970: 1_792_500_000_000),
        endedAt: Timestamp(millisecondsSince1970: 1_792_501_920_000), summary: WorkoutSummary(durationSec: 1920),
        route: [RoutePoint(lat: 40.78, lon: -73.96), RoutePoint(lat: 40.79, lon: -73.97)], tilePosition: 2)
    let first = PreparedPhoto(id: id(601), jpeg: Data([1]), size: nil)
    let second = PreparedPhoto(id: id(602), jpeg: Data([2]), size: nil)
    let body = PostBody(photos: [first, second], caption: "晨跑", workout: workout)
    #expect(
        ComposedTile.of(body).map(\.id) == ["new:\(first.id.uuidString)", "workout.map", "new:\(second.id.uuidString)"])
    #expect(ComposedTile.of(PostBody(photos: [], caption: "")).isEmpty)
}
