import AvatarArt
import Contracts
import Foundation
import Testing

@testable import FeedDomain
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

/// Each sample post's photo comes back by the name it was rendered under.
@MainActor @Test func theSamplePhotosLoadByName() async throws {
    let photos = Dictionary(uniqueKeysWithValues: InMemoryFeedSource.samplePhotoNames.map { ($0, Data($0.utf8)) })
    let source = InMemoryFeedSource.sample(viewer: viewer, squad: squad, now: thursday, zone: newYork, photos: photos)
    let today = LocalDay(at: thursday, in: newYork)
    let feed = FeedStore(source: source, squad: squad, viewer: viewer, today: { today }, now: { Timestamp(thursday) })
    await feed.load()
    let refs = feed.sections.flatMap(\.posts).flatMap { post -> [PhotoRef] in
        switch post.checkIn.entry {
        case .trained(let training): training.photos?.all ?? []
        case .healthyMeal(let meal), .cheatMeal(let meal): meal.photos?.all ?? []
        case .disclaimer(let disclaimer): disclaimer.photos?.all ?? []
        }
    }
    #expect(refs.count == 6)
    var loaded: [String] = []
    for ref in refs {
        let data = try #require(await feed.photo(ref))
        loaded.append(try #require(String(bytes: data, encoding: .utf8)))
    }
    #expect(Set(loaded) == Set(InMemoryFeedSource.samplePhotoNames))
}

/// Every move an emoji asks for is drawn, for every persona; the rest cheer.
@Test func everyEmojiMoveIsDrawnForEveryPersona() {
    let moves = Set(MoveID.byEmoji.values.map(\.id))
    #expect(moves.isSubset(of: PlaceholderCharacter.reactionMoves))
    for persona in Persona.allCases {
        #expect(moves.allSatisfy { PlaceholderCharacter.reactionMove($0, persona: persona) != nil }, "\(persona)")
    }
    #expect(PlaceholderCharacter.reactionMove(MoveID.cheer.id) == nil)
}
