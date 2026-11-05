import Contracts
import Foundation
import Testing

@testable import FeedDomain

private let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")
private let people = [jay: "Jay", mia: "Mia", coco: "Coco"]

@Test func thePickerListsTheCoachFirstThenEveryoneButTheViewer() {
    let all = CommentDraft.candidates(for: "", coach: maotou, people: people, viewer: coco)
    #expect(all == [.coach(maotou), .member(jay, name: "Jay"), .member(mia, name: "Mia")])
    #expect(
        CommentDraft.candidates(for: "m", coach: maotou, people: people, viewer: coco) == [.member(mia, name: "Mia")])
    #expect(CommentDraft.candidates(for: "毛", coach: maotou, people: people, viewer: coco) == [.coach(maotou)])
    // Without a coach, only people.
    #expect(CommentDraft.candidates(for: "", coach: nil, people: people, viewer: coco).count == 2)
}

@Test func typingAnAtAsksWhoUntilASpace() {
    var draft = CommentDraft()
    draft.text = "明天 @J"
    #expect(draft.mentionQuery == "J")
    draft.text = "明天 @Jay 一起"
    #expect(draft.mentionQuery == nil)
    draft.text = "没有"
    #expect(draft.mentionQuery == nil)
}

@Test func pickingPutsTheNameInAndTheWordsDecideWhoIsMentioned() {
    var draft = CommentDraft()
    draft.text = "明天 @J"
    draft.pick(.member(jay, name: "Jay"))
    #expect(draft.text == "明天 @Jay ")
    // The 「@毛头」 button adds at the end.
    draft.text += "一起"
    draft.pick(.coach(maotou))
    #expect(draft.text == "明天 @Jay 一起 @毛头 ")
    #expect(draft.mentions == Mentions(members: [jay], coach: "xiaohun"))
    // Deleting 「@Jay」 takes it back.
    draft.text = "明天一起 @毛头 "
    #expect(draft.mentions == Mentions(members: [], coach: "xiaohun"))
    draft.clear()
    #expect(draft.mentions.isEmpty && draft.text.isEmpty)
}

@Test func aCommentMentionsAtMostEightEachOnce() {
    let many = (1...10).map { MemberID(uuid(500 + $0)) }
    #expect(Mentions(members: many + [many[0]], coach: nil).members == Array(many.prefix(8)))
    var draft = CommentDraft()
    for (index, member) in many.prefix(8).enumerated() { draft.pick(.member(member, name: "队员\(index)")) }
    #expect(draft.canMentionMore == false)
}

@MainActor @Test func aCommentGoesOutWithWhomItMentions() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    let mentions = Mentions(members: [mia], coach: "xiaohun")
    #expect(await feed.comment(text("@Mia @毛头 来"), replyingTo: nil, mentioning: mentions, on: jaysRun.id))
    #expect(await source.mentioned == [mentions])
    #expect(feed.post(jaysRun.id)?.comments.first?.mentions == mentions)
}
