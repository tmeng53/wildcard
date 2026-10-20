import Contracts
import Testing

@testable import FeedDomain

let author = member(1)
let coco = member(2)
let mia = member(3)
let jay = member(4)
let doudou = member(5)

@Test func eachMemberKeepsOnlyTheirLatestEmoji() {
    let responses = reactions([(coco, "❤️", 10), (mia, "😂", 20), (coco, "💪", 30)])
    #expect(responses.kind(of: coco) == emoji("💪"))
    #expect(responses.count(of: emoji("❤️")) == 0)
    #expect(responses.count(of: emoji("😂")) == 1)
    #expect(responses.all.map(\.member) == [mia, coco])
}

@Test func groupsRunMostLeftFirstThenFirstLeftAndListMembersOldestFirst() {
    let responses = reactions([
        (mia, "😂", 10), (jay, "❤️", 20), (coco, "❤️", 5), (doudou, "🤤", 30), (author, "😮", 40),
    ])
    #expect(
        responses.groups == [
            .init(kind: emoji("❤️"), members: [coco, jay]),
            .init(kind: emoji("😂"), members: [mia]),
            .init(kind: emoji("🤤"), members: [doudou]),
            .init(kind: emoji("😮"), members: [author]),
        ])
    #expect(responses.topKinds(3) == [emoji("❤️"), emoji("😂"), emoji("🤤")])
}

@Test func theFacesAreTheLatestThreeNewestFirst() {
    let responses = reactions([(coco, "❤️", 10), (mia, "😂", 20), (jay, "❤️", 30), (doudou, "💪", 40)])
    #expect(responses.latestMembers(3) == [doudou, jay, mia])
}

@Test func anyEmojiCanBeLeft() throws {
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"))
    let change = try post.reacting(.pick(emoji("🦖")), by: coco, at: at(50))
    #expect(change.now == emoji("🦖"))
    #expect(change.before == nil)
    #expect(change.changed)
    #expect(change.post.reactions.count(of: emoji("🦖")) == 1)
}

@Test func pickingAnotherEmojiSwapsIt() throws {
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, "❤️", 10)]))
    let change = try post.reacting(.pick(emoji("😂")), by: coco, at: at(50))
    #expect(change.post.reactions.count(of: emoji("❤️")) == 0)
    #expect(change.post.reactions.count(of: emoji("😂")) == 1)
}

@Test func pickingTheSameEmojiAgainTakesItBack() throws {
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, "❤️", 10)]))
    let change = try post.reacting(.pick(.heart), by: coco, at: at(50))
    #expect(change.now == nil)
    #expect(change.post.reactions.isEmpty)
}

@Test func aDoubleTapLeavesAHeartAndNeverTakesItBack() throws {
    let hearted = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, "❤️", 10)]))
    let again = try hearted.reacting(.doubleTap, by: coco, at: at(50))
    #expect(again.now == .heart)
    #expect(!again.changed)
    #expect(again.post.reactions.count(of: .heart) == 1)

    let laughed = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, "😂", 10)]))
    let switched = try laughed.reacting(.doubleTap, by: coco, at: at(50))
    #expect(switched.before == emoji("😂"))
    #expect(switched.now == .heart)
    #expect(switched.post.reactions.count(of: emoji("😂")) == 0)
}

@Test func nobodyRespondsToTheirOwnPost() {
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20", disclaimer: true))
    #expect(throws: FeedError.ownPost) { try post.reacting(.doubleTap, by: author, at: at(1)) }
    #expect(throws: FeedError.ownPost) { try post.replying(.approved, by: author, at: at(1)) }
}

@Test func repliesGoOnADisclaimerOnlyAndApartFromReactions() throws {
    let training = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"))
    #expect(throws: FeedError.notADisclaimer) { try training.replying(.hug, by: coco, at: at(1)) }

    let slip = FeedPost(
        checkIn: checkIn(2, by: author, on: "2026-10-20", disclaimer: true), reactions: reactions([(coco, "😂", 5)]))
    let change = try slip.replying(.approved, by: coco, at: at(10))
    #expect(change.post.replies.kind(of: coco) == .approved)
    #expect(change.post.reactions.kind(of: coco) == emoji("😂"))

    let takenBack = try change.post.replying(.approved, by: coco, at: at(20))
    #expect(takenBack.now == nil)
    #expect(takenBack.post.replies.isEmpty)
}

@Test func aPostThatIsNotADisclaimerDropsReplies() {
    let replies = Responses<ReplyKind>([Reply(member: coco, kind: .hug, repliedAt: at(1))])
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), replies: replies)
    #expect(post.replies.isEmpty)
}
