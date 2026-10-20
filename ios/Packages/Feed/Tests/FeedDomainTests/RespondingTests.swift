import Contracts
import Testing

@testable import FeedDomain

let author = member(1)
let coco = member(2)
let mia = member(3)
let jay = member(4)
let doudou = member(5)

@Test func eachMemberKeepsOnlyTheirLatestReaction() {
    let responses = reactions([(coco, .cheer, 10), (mia, .lol, 20), (coco, .highlight, 30)])
    #expect(responses.kind(of: coco) == .highlight)
    #expect(responses.count(of: .cheer) == 0)
    #expect(responses.count(of: .highlight) == 1)
    #expect(responses.count(of: .lol) == 1)
    #expect(responses.all.map(\.member) == [mia, coco])
}

@Test func groupsFollowTheReactionOrderAndListMembersOldestFirst() {
    let responses = reactions([(mia, .lol, 10), (jay, .cheer, 20), (coco, .cheer, 5)])
    #expect(
        responses.groups == [
            .init(kind: .cheer, members: [coco, jay]),
            .init(kind: .lol, members: [mia]),
        ])
}

@Test func theFacesAreTheLatestThreeNewestFirst() {
    let responses = reactions([(coco, .cheer, 10), (mia, .lol, 20), (jay, .cheer, 30), (doudou, .highlight, 40)])
    #expect(responses.latestMembers(3) == [doudou, jay, mia])
}

@Test func aNewReactionPlaysItsMove() throws {
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"))
    let change = try post.reacting(.pick(.highlight), by: coco, at: at(50))
    #expect(change.now == .highlight)
    #expect(change.before == nil)
    #expect(change.move == .pose)
    #expect(change.changed)
    #expect(change.post.reactions.count(of: .highlight) == 1)
}

@Test func pickingAnotherReactionMovesIt() throws {
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, .cheer, 10)]))
    let change = try post.reacting(.pick(.lol), by: coco, at: at(50))
    #expect(change.post.reactions.count(of: .cheer) == 0)
    #expect(change.post.reactions.count(of: .lol) == 1)
    #expect(change.move == .laugh)
}

@Test func pickingTheSameReactionAgainTakesItBackWithoutAMove() throws {
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, .cheer, 10)]))
    let change = try post.reacting(.pick(.cheer), by: coco, at: at(50))
    #expect(change.now == nil)
    #expect(change.move == nil)
    #expect(change.post.reactions.isEmpty)
}

@Test func aDoubleTapCheersAndNeverTakesTheCheerBack() throws {
    let cheered = FeedPost(
        checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, .cheer, 10)]))
    let again = try cheered.reacting(.doubleTap, by: coco, at: at(50))
    #expect(again.now == .cheer)
    #expect(!again.changed)
    #expect(again.move == .pump)
    #expect(again.post.reactions.count(of: .cheer) == 1)

    let laughed = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), reactions: reactions([(coco, .lol, 10)]))
    let switched = try laughed.reacting(.doubleTap, by: coco, at: at(50))
    #expect(switched.before == .lol)
    #expect(switched.now == .cheer)
    #expect(switched.post.reactions.count(of: .lol) == 0)
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
        checkIn: checkIn(2, by: author, on: "2026-10-20", disclaimer: true), reactions: reactions([(coco, .lol, 5)]))
    let change = try slip.replying(.approved, by: coco, at: at(10))
    #expect(change.move == .wave)
    #expect(change.post.replies.kind(of: coco) == .approved)
    #expect(change.post.reactions.kind(of: coco) == .lol)

    let takenBack = try change.post.replying(.approved, by: coco, at: at(20))
    #expect(takenBack.now == nil)
    #expect(takenBack.move == nil)
    #expect(takenBack.post.replies.isEmpty)
}

@Test func aPostThatIsNotADisclaimerDropsReplies() {
    let replies = Responses<ReplyKind>([Reply(member: coco, kind: .hug, repliedAt: at(1))])
    let post = FeedPost(checkIn: checkIn(1, by: author, on: "2026-10-20"), replies: replies)
    #expect(post.replies.isEmpty)
}

@Test func everyReactionHasItsOwnMove() {
    #expect(ReactionKind.allCases.map(CharacterMove.init) == [.pump, .pose, .laugh])
    #expect(ReplyKind.allCases.map(CharacterMove.init) == [.wave, .wave, .wave])
}
