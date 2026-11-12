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
    let store = FeedStore(
        source: source, squad: squad, viewer: viewer, today: { today }, now: { Timestamp(thursday) },
        newCommentID: { CommentID(UUID()) })
    await store.load()
    return (store, source)
}

/// The reviewed squad: three days, every kind, posts from Apple Health, names for everyone, my own post among them.
@MainActor @Test func theSampleCoversEveryKindOverThreeDays() async {
    let (feed, _) = await sampleFeed()
    #expect(feed.sections.map(\.heading) == [.today, .yesterday, .weekday(2)])
    let posts = feed.sections.flatMap(\.posts)
    #expect(posts.count == 8)
    #expect(posts.contains { $0.author == viewer })
    // Four 训练 come from Apple Health: two with their map, the swim with its laps, my strength
    // session with its heart rate after its photo.
    let tiles = posts.compactMap { post -> [Contracts.PostTile]? in
        guard case .trained(let training) = post.checkIn.entry, training.workout != nil else { return nil }
        return training.tiles
    }
    #expect(tiles.count == 4)
    #expect(tiles.contains([.workout(.map)]))
    #expect(tiles.contains { $0.count == 2 && $0.first != .workout(.chart) && $0.last == .workout(.chart) })
    #expect(tiles.contains { $0.count == 2 && $0.last == .workout(.chart) })
    #expect(posts.allSatisfy { feed.characters[$0.author] != nil })
    let disclaimer = posts.first {
        if case .disclaimer = $0.checkIn.entry { true } else { false }
    }
    #expect(disclaimer?.reactions.all.count == 3)
    #expect(feed.characters[viewer]?.look.variants["body"] == "peach")
}

/// My run only recorded (发布到动态 off) is on my own wall, first, and never in the squad's 动态.
@MainActor @Test func myUnpostedRunIsOnlyOnMyWall() async throws {
    let (feed, source) = await sampleFeed()
    #expect(!feed.sections.flatMap(\.posts).contains { !$0.checkIn.inFeed })
    let wall = try await source.myPosts(kind: nil, after: nil)
    #expect(wall.posts.count == 2)
    #expect(wall.posts.first?.checkIn.inFeed == false)
    #expect(wall.posts.last?.checkIn.inFeed == true)
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

/// Each sample post's photo comes back by the name it was rendered under, with its size.
@MainActor @Test func theSamplePhotosLoadByName() async throws {
    let names = Array(InMemoryFeedSource.samplePhotoSizes.keys)
    let photos = Dictionary(uniqueKeysWithValues: names.map { ($0, Data($0.utf8)) })
    let source = InMemoryFeedSource.sample(viewer: viewer, squad: squad, now: thursday, zone: newYork, photos: photos)
    let today = LocalDay(at: thursday, in: newYork)
    let feed = FeedStore(
        source: source, squad: squad, viewer: viewer, today: { today }, now: { Timestamp(thursday) },
        newCommentID: { CommentID(UUID()) })
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
        let name = try #require(String(bytes: data, encoding: .utf8))
        loaded.append(name)
        #expect(ref.size?.width == InMemoryFeedSource.samplePhotoSizes[name]?.width)
        #expect(ref.size?.height == InMemoryFeedSource.samplePhotoSizes[name]?.height)
    }
    #expect(Set(loaded) == Set(names))
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
