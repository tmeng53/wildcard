import Contracts
import Foundation
import Testing

@testable import FeedDomain

@MainActor @Test func aReportedPostLeavesOnceTheServerTookIt() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    #expect(await feed.report(.post(jaysRun.id)))
    #expect(feed.post(jaysRun.id) == nil)
    #expect(await source.calls.last == .report(.post(jaysRun.id)))
}

@MainActor @Test func aReportThatCantGoOutKeepsThePostAndSaysWhy() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    await source.fail(with: .notSent)
    #expect(await feed.report(.post(jaysRun.id)) == false)
    #expect(feed.post(jaysRun.id) != nil)
    #expect(feed.failure == .notSent)
}

@MainActor @Test func aReportedCommentLeavesItsPost() async {
    let post = FeedPost(checkIn: jaysRun.checkIn, comments: [comment(1, by: mia, "一"), comment(2, by: jay, "二")])
    let feed = store(FakeSource([post]))
    await feed.load()
    #expect(await feed.report(.comment(commentID(1), post: post.id)))
    #expect(feed.post(post.id)?.comments.map(\.id) == [commentID(2)])
}

@MainActor @Test func aBlockedTeammatesPostsCommentsAndReactionsLeave() async {
    let miasRun = FeedPost(checkIn: checkIn(2, by: mia, on: "2026-10-19"))
    let post = FeedPost(
        checkIn: jaysRun.checkIn, reactions: reactions([(mia, "💪", 10), (coco, "😂", 20)]),
        comments: [comment(1, by: mia, "一"), comment(2, by: coco, "二")])
    let feed = store(FakeSource([post, miasRun]))
    await feed.load()
    #expect(await feed.block(mia))
    #expect(feed.post(miasRun.id) == nil)
    #expect(feed.post(post.id)?.comments.map(\.id) == [commentID(2)])
    #expect(feed.post(post.id)?.reactions.all.map(\.member) == [coco])
}

@MainActor @Test func aReportedCoachLineLeavesTheCoach() async {
    let coach = FeedCoach(source: OneReply(), squad: squad, now: { Date() })
    await coach.load(about: [jaysRun.id])
    #expect(coach.reply(to: jaysRun.id)?.text == "跑得好")
    coach.hide(.coachReply("xiaohun", post: jaysRun.id, squad: squad))
    #expect(coach.reply(to: jaysRun.id) == nil)
}

private struct OneReply: CoachSource {
    func activity(in squad: SquadID, about checkIns: [CheckInID]) async throws(FeedError) -> CoachActivity {
        let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")
        let reply = CoachReply(checkIn: jaysRun.id, coach: maotou, text: "跑得好", emoji: nil, writtenAt: Date())
        return CoachActivity(note: nil, replies: [reply])
    }
    func hiredCoach(in squad: SquadID) async throws(FeedError) -> CoachSpeaker? { nil }
}
