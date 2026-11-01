import AvatarArt
import AvatarDomain
import Contracts
import DailyPushDomain
import DailyPushUI
import Foundation
import Testing

private let noon = Date(timeIntervalSince1970: 1_792_756_800)  // 2026-10-23T12:00:00Z
private let utc = TimeZone(identifier: "UTC") ?? .current

@Test func theSampleIsAPushTheViewCanRead() throws {
    let push = try #require(DailyPushSample.push(empty: false, now: noon, zone: utc))
    #expect(push.posts.map { push.name(of: $0.author) } == ["阿杰", "豆豆", "Leo", "小米"])
    #expect(
        push.posts.map(\.posted.description) == [
            "2026-10-23T17:42:00.000Z", "2026-10-23T16:10:00.000Z", "2026-10-23T12:30:00.000Z",
            "2026-10-23T07:15:00.000Z",
        ])
    #expect(push.more == 2)
    #expect(push.pokedBy.map { push.name(of: $0) } == ["小米"])
    #expect(push.squadWeek == WeekCount(trainedDays: 9, plannedDays: 16))
    // Everyone who posted has a look.
    #expect(push.posts.allSatisfy { DailyPushSample.looks[$0.author] != nil })
}

@Test func theEmptySampleHasNoPosts() throws {
    let push = try #require(DailyPushSample.push(empty: true, now: noon, zone: utc))
    #expect(push.posts.isEmpty)
    #expect(push.more == 0)
}

@Test func everySampleLookIsDrawnFromArtThisBuildHas() throws {
    for look in DailyPushSample.looks.values {
        for (slot, variant) in look.variants {
            #expect(PlaceholderCharacter.variants(for: Slot(slot)).contains(variant), "\(slot): \(variant)")
        }
        _ = try PlaceholderCharacter.figure(wearing: Outfit(look))
    }
}
