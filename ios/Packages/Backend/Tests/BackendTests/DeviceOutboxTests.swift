import CheckInDomain
import Contracts
import Foundation
import Testing

@testable import Backend

// The outbox on disk, without the API: what goes in comes back out after the app reopens.

@Test func aWaitingTrainingKeepsItsSportAndMinutesOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let squad = SquadID(try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")))
    let post = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        member: MemberID(try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))),
        day: try LocalDay("2026-10-23"), createdAt: Timestamp(millisecondsSince1970: 1_792_727_000_000),
        audience: try Audience([squad]),
        draft: .trained(.sport("run"), try WorkoutMinutes(45), PostBody(photos: [], caption: "雨中五公里")))
    let untimed = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))),
        member: post.member, day: post.day, createdAt: post.createdAt, audience: post.audience,
        draft: .trained(.custom(try CustomSport("飞盘")), nil, PostBody(photos: [], caption: "")))

    await DeviceOutbox(directory: directory).save([post, untimed])

    #expect(await DeviceOutbox(directory: directory).load() == [post, untimed])
}

@Test func aWaitingTrainingKeepsItsStartTimeOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let squad = SquadID(try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")))
    let post = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        member: MemberID(try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))),
        day: try LocalDay("2026-11-08"), createdAt: Timestamp(millisecondsSince1970: 1_794_000_000_000),
        audience: try Audience([squad]),
        draft: .trained(
            .sport("run"), try WorkoutMinutes(30),
            PostBody(photos: [], caption: "早起", startTime: try StartTime(hour: 6, minute: 5))))

    await DeviceOutbox(directory: directory).save([post])

    let loaded = await DeviceOutbox(directory: directory).load()
    #expect(loaded == [post])
    guard case .trained(_, _, let body) = try #require(loaded.first).draft else {
        Issue.record("the waiting post isn't a 训练")
        return
    }
    #expect(body.startTime?.wire == "06:05")
}

@Test func aWaitingMealKeepsItsPlaceOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let squad = SquadID(try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")))
    let place = try Place(
        name: "Sweetgreen", appleID: "I1A2B3", category: "restaurant", latitude: 40.7448, longitude: -73.9881)
    let post = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        member: MemberID(try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))),
        day: try LocalDay("2026-11-12"), createdAt: Timestamp(millisecondsSince1970: 1_794_500_000_000),
        audience: try Audience([squad]), draft: .healthyMeal(PostBody(photos: [], caption: "沙拉", place: place)))

    await DeviceOutbox(directory: directory).save([post])

    let loaded = await DeviceOutbox(directory: directory).load()
    #expect(loaded == [post])
    guard case .healthyMeal(let body) = try #require(loaded.first).draft else {
        Issue.record("the waiting post isn't a 健康餐")
        return
    }
    #expect(body.place?.name == "Sweetgreen")
}

@Test func aWaitingMealKeepsItsRatingOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let squad = SquadID(try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")))
    let rating = try MealRating(healthy: 2, tasty: 5)
    let post = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        member: MemberID(try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))),
        day: try LocalDay("2026-11-12"), createdAt: Timestamp(millisecondsSince1970: 1_794_500_000_000),
        audience: try Audience([squad]), draft: .cheatMeal(PostBody(photos: [], caption: "火锅", rating: rating)))

    await DeviceOutbox(directory: directory).save([post])

    let loaded = await DeviceOutbox(directory: directory).load()
    #expect(loaded == [post])
    guard case .cheatMeal(let body) = try #require(loaded.first).draft else {
        Issue.record("the waiting post isn't a 坦白放纵餐")
        return
    }
    #expect(body.rating == rating)
}

@Test func aWaitingPostKeepsItsPhotosSizesOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let portrait = try PhotoSize(width: 1080, height: 1350)
    let landscape = try PhotoSize(width: 1080, height: 720)
    let sent = PreparedPhoto(id: UUID(), jpeg: Data(), size: portrait)
    let waiting = PreparedPhoto(id: UUID(), jpeg: Data([0xFF, 0xD8]), size: landscape)
    let post = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        member: MemberID(try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))),
        day: try LocalDay("2026-10-24"), createdAt: Timestamp(millisecondsSince1970: 1_792_813_400_000),
        audience: try Audience([SquadID(try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")))]),
        draft: .healthyMeal(PostBody(photos: [sent, waiting], caption: "")),
        uploaded: [sent.id: try PhotoRef(path: "22222222-2222-2222-2222-222222222222/sent")])

    await DeviceOutbox(directory: directory).save([post])

    let kept = try #require(await DeviceOutbox(directory: directory).load().first)
    #expect(kept.draft.photos.map(\.size) == [portrait, landscape])
    #expect(kept == post)
}

@Test func aWaitingTrainingKeepsItsWorkoutOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "A1"),
        startedAt: Timestamp(millisecondsSince1970: 1_792_725_080_000),
        endedAt: Timestamp(millisecondsSince1970: 1_792_727_000_000),
        summary: WorkoutSummary(durationSec: 1920, distanceM: 5200, avgHr: 148),
        route: [RoutePoint(lat: 40.78, lon: -73.96), RoutePoint(lat: 40.79, lon: -73.95)], tilePosition: 1)
    let post = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        member: MemberID(try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))),
        day: try LocalDay("2026-10-23"), createdAt: Timestamp(millisecondsSince1970: 1_792_727_000_000),
        audience: try Audience([]),
        draft: .trained(.sport("run"), try WorkoutMinutes(32), PostBody(photos: [], caption: "", workout: workout)))

    await DeviceOutbox(directory: directory).save([post])

    let kept = try #require(await DeviceOutbox(directory: directory).load().first)
    #expect(kept.draft.workout == workout)
    #expect(kept == post)
}

@Test func aWaitingDisclaimerKeepsItsPhotosOnDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let sent = PreparedPhoto(id: UUID(), jpeg: Data(), size: try PhotoSize(width: 1080, height: 1440))
    let waiting = PreparedPhoto(id: UUID(), jpeg: Data([0xFF, 0xD8]), size: try PhotoSize(width: 1080, height: 720))
    let post = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        member: MemberID(try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))),
        day: try LocalDay("2026-11-10"), createdAt: Timestamp(millisecondsSince1970: 1_794_270_000_000),
        audience: try Audience([SquadID(try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")))]),
        draft: .disclaimer(try Disclaimer("下大雨，在家给猫当沙发"), photos: [sent, waiting]),
        uploaded: [sent.id: try PhotoRef(path: "22222222-2222-2222-2222-222222222222/sent")])

    await DeviceOutbox(directory: directory).save([post])

    let kept = try #require(await DeviceOutbox(directory: directory).load().first)
    #expect(kept.draft.photos.map(\.id) == [sent.id, waiting.id])
    #expect(kept == post)
}
