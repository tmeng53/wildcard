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
        draft: .trained(.sport(.run), try WorkoutMinutes(45), PostBody(photos: [], caption: "雨中五公里")))
    let untimed = PendingCheckIn(
        id: CheckInID(try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))),
        member: post.member, day: post.day, createdAt: post.createdAt, audience: post.audience,
        draft: .trained(.custom(try CustomSport("飞盘")), nil, PostBody(photos: [], caption: "")))

    await DeviceOutbox(directory: directory).save([post, untimed])

    #expect(await DeviceOutbox(directory: directory).load() == [post, untimed])
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
