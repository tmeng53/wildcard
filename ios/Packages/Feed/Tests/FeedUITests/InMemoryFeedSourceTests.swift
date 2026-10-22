import Contracts
import FeedDomain
import Foundation
import Testing

@testable import FeedUI

private let viewer = MemberID(UUID())
private let squad = SquadID(UUID())
/// Thursday 2026-10-22, 15:00 in New York.
private let thursday = Date(timeIntervalSince1970: 1_792_695_600)
private let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

@MainActor
private func sampleFeed() async -> (FeedStore, InMemoryFeedSource) {
    let source = InMemoryFeedSource.sample(viewer: viewer, squad: squad, now: thursday, zone: newYork)
    let today = LocalDay(at: thursday, in: newYork)
    let store = FeedStore(source: source, squad: squad, viewer: viewer, today: { today }, now: { Timestamp(thursday) })
    await store.load()
    return (store, source)
}

/// The reviewed squad: three days, every kind, names for everyone, my own post among them.
@MainActor @Test func theSampleCoversEveryKindOverThreeDays() async {
    let (feed, _) = await sampleFeed()
    #expect(feed.sections.map(\.heading) == [.today, .yesterday, .weekday(2)])
    let posts = feed.sections.flatMap(\.posts)
    #expect(posts.count == 7)
    #expect(posts.contains { $0.author == viewer })
    #expect(posts.allSatisfy { feed.characters[$0.author] != nil })
    let disclaimer = posts.first {
        if case .disclaimer = $0.checkIn.entry { true } else { false }
    }
    #expect(disclaimer?.reactions.all.count == 3)
    #expect(feed.characters[viewer]?.look.variants["body"] == "peach")
}

/// Reactions go through the in-memory server as through the API: one each, never on my own.
@MainActor @Test func reactionsStickAndMyOwnPostRefusesThem() async throws {
    let (feed, _) = await sampleFeed()
    let posts = feed.sections.flatMap(\.posts)
    let run = try #require(posts.first { $0.author != viewer })
    let mine = try #require(posts.first { $0.author == viewer })
    let heart = try Emoji("❤️")
    try feed.react(.pick(heart), on: run.id)
    await feed.sendResponses()
    await feed.load()
    #expect(feed.post(run.id)?.reactions.kind(of: viewer) == heart)
    #expect(throws: FeedError.ownPost) { try feed.react(.doubleTap, on: mine.id) }
}
