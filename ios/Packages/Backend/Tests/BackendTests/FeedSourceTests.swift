import Contracts
import FeedDomain
import Foundation
import Testing

@testable import Backend

// 动态's adapter against the built API and local Supabase: a teammate's post with its photo and
// character, and reacting to it, as the feed does.

@Test func aTeammateSeesThePostItsPhotoAndCharacterAndReactsToIt() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let character = MemberCharacter(
        nickname: try Nickname("小周"), look: CharacterLook(persona: "deadpan", variants: ["body": "tuxedo"], colors: [:])
    )
    _ = try await author.api.save(Profile(timeZone: try #require(TimeZone(identifier: "UTC")), character: character))
    let bytes = photoBytes()
    let photo = try await author.api.upload(bytes, as: .jpeg)
    let meal = try checkIn(by: author, to: squad, .healthyMeal(Meal(photos: try Photos([photo]))))
    _ = try await author.api.save(meal)

    let feed = APIFeedSource(api: mate.api)
    let posts = try await feed.posts(in: squad, from: meal.day, through: meal.day)
    #expect(posts.map(\.id) == [meal.id])
    #expect(try #require(posts.first).reactions.isEmpty)
    #expect(try await feed.characters(in: squad)[author.id] == character)
    guard case .healthyMeal(let seen) = try #require(posts.first).checkIn.entry else {
        Issue.record("mate saw \(posts)")
        return
    }
    #expect(await feed.photo(try #require(seen.photos?.cover)) == bytes)

    try await feed.setReaction(try Emoji("💪"), on: meal.id)
    let reacted = try await APIFeedSource(api: author.api).posts(in: squad, from: meal.day, through: meal.day)
    #expect(try #require(reacted.first).reactions.all.map(\.member) == [mate.id])
    #expect(try #require(reacted.first).reactions.all.map(\.kind) == [try Emoji("💪")])

    // Taking it back leaves none, and taking it back again is fine.
    try await feed.setReaction(nil, on: meal.id)
    try await feed.setReaction(nil, on: meal.id)
    #expect(try await feed.posts(in: squad, from: meal.day, through: meal.day).first?.reactions.isEmpty == true)
}

@Test func aMemberOutsideTheSquadIsToldSo() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let outsider = try await stack.signedInMember()
    let squad = try await stack.squad(of: author)
    let day = try moment().day
    await #expect(throws: FeedError.notInSquad) {
        try await APIFeedSource(api: outsider.api).posts(in: squad, from: day, through: day)
    }
}
