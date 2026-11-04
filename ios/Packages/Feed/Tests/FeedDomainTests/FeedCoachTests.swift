import Contracts
import FeedDomain
import Foundation
import Testing

/// The coach's words as a server would keep them, recording what each read asked about.
private actor FakeCoach: CoachSource {
    var activity: CoachActivity
    var failure: FeedError?
    private(set) var asked: [[CheckInID]] = []

    init(_ activity: CoachActivity) { self.activity = activity }

    func set(_ activity: CoachActivity) { self.activity = activity }
    func fail(with error: FeedError?) { failure = error }

    func activity(in squad: SquadID, about checkIns: [CheckInID]) async throws(FeedError) -> CoachActivity {
        asked.append(checkIns)
        if let failure { throw failure }
        return CoachActivity(
            note: activity.note, replies: activity.replies.filter { checkIns.contains($0.checkIn) },
            answers: activity.answers.filter { checkIns.contains($0.checkIn) })
    }
}

private let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")
/// 2026-10-20 07:00 in New York.
private let sevenAM = Date(timeIntervalSince1970: 1_792_494_000)

private func reply(_ number: Int, _ text: String?, _ face: String?) -> CoachReply {
    CoachReply(
        checkIn: checkInID(number), coach: maotou, text: text, emoji: face.map(emoji), writtenAt: sevenAM)
}

private let note = CoachNote(day: day("2026-10-20"), text: "今天谁先动，谁就是队长", coach: maotou, writtenAt: sevenAM)

@MainActor @Test func showsTheLineOnlyOnItsDay() async {
    let coach = FeedCoach(source: FakeCoach(CoachActivity(note: note, replies: [])), squad: squad) { sevenAM }
    await coach.load(about: [])
    #expect(coach.todaysNote?.text == "今天谁先动，谁就是队长")

    // 4am the next day in New York: the line's day is over.
    let nextDay = sevenAM.addingTimeInterval(21 * 3600)
    let later = FeedCoach(source: FakeCoach(CoachActivity(note: note, replies: [])), squad: squad) { nextDay }
    await later.load(about: [])
    #expect(later.note?.text == "今天谁先动，谁就是队长")
    #expect(later.todaysNote == nil)
}

@MainActor @Test func readsRepliesToThePostsShown() async {
    let source = FakeCoach(CoachActivity(note: nil, replies: [reply(1, "稳", "🔥"), reply(2, nil, "💪")]))
    let coach = FeedCoach(source: source, squad: squad) { sevenAM }
    await coach.load(about: [checkInID(1), checkInID(3)])

    #expect(coach.reply(to: checkInID(1))?.text == "稳")
    #expect(coach.reply(to: checkInID(1))?.emoji == emoji("🔥"))
    #expect(coach.reply(to: checkInID(2)) == nil)
    #expect(coach.reply(to: checkInID(3)) == nil)

    // The week before asks only for its own posts.
    await coach.loadNew([checkInID(1), checkInID(2)])
    #expect(await source.asked == [[checkInID(1), checkInID(3)], [checkInID(2)]])
    #expect(coach.reply(to: checkInID(2))?.emoji == emoji("💪"))
    #expect(coach.reply(to: checkInID(2))?.text == nil)

    await coach.loadNew([checkInID(2)])
    #expect(await source.asked.count == 2)
}

@MainActor @Test func asksAboutTheNewestHundredAtMost() async {
    let source = FakeCoach(CoachActivity(note: nil, replies: []))
    let coach = FeedCoach(source: source, squad: squad) { sevenAM }
    await coach.load(about: (1...130).map(checkInID))
    #expect(await source.asked.first?.count == 100)
    #expect(await source.asked.first?.last == checkInID(100))
}

@MainActor @Test func keepsWhatItReadOffline() async {
    let source = FakeCoach(CoachActivity(note: note, replies: [reply(1, "稳", nil)]))
    let coach = FeedCoach(source: source, squad: squad) { sevenAM }
    await coach.load(about: [checkInID(1)])

    await source.fail(with: .notSent)
    await coach.load(about: [checkInID(1)])
    #expect(coach.todaysNote?.text == "今天谁先动，谁就是队长")
    #expect(coach.reply(to: checkInID(1))?.text == "稳")
}

@MainActor @Test func aReplyThatCameLaterShowsOnTheNextRead() async {
    let source = FakeCoach(CoachActivity(note: nil, replies: []))
    let coach = FeedCoach(source: source, squad: squad) { sevenAM }
    await coach.load(about: [checkInID(1)])
    #expect(coach.reply(to: checkInID(1)) == nil)

    await source.set(CoachActivity(note: note, replies: [reply(1, "可以", "👏")]))
    await coach.load(about: [checkInID(1)])
    #expect(coach.reply(to: checkInID(1))?.text == "可以")
    #expect(coach.todaysNote != nil)
}

@MainActor @Test func readsItsAnswersToRepliesAndForgetsOnesThatWent() async {
    let answer = CoachAnswer(
        checkIn: checkInID(1), comment: commentID(4), coach: maotou, text: "我负责喊", writtenAt: sevenAM)
    let source = FakeCoach(CoachActivity(note: nil, replies: [reply(1, "稳", nil)], answers: [answer]))
    let coach = FeedCoach(source: source, squad: squad) { sevenAM }
    await coach.load(about: [checkInID(1), checkInID(2)])
    #expect(coach.answers(on: checkInID(1)) == [answer])
    #expect(coach.answers(on: checkInID(2)).isEmpty)
    // 回复 毛头 names the coach as it spoke.
    #expect(coach.speaker("xiaohun")?.name == "毛头")
    #expect(coach.speaker("other") == nil)

    // The reply was deleted, and its answer with it.
    await source.set(CoachActivity(note: nil, replies: [reply(1, "稳", nil)]))
    await coach.load(about: [checkInID(1)])
    #expect(coach.answers(on: checkInID(1)).isEmpty)
}
