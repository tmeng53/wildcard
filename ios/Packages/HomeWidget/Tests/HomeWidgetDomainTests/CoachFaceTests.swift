import CheckInDomain
import Contracts
import Foundation
import HomeWidgetDomain
import Testing

private let squad = SquadID(UUID(uuidString: "00000000-0000-0000-0000-000000000010") ?? UUID())
private let newYork = TimeZone(identifier: "America/New_York") ?? .gmt
/// Tuesday 2026-10-20, 9:00 in New York.
private let morning = Date(timeIntervalSince1970: 1_792_501_200)
private let tuesday = LocalDay(at: morning, in: newYork)
private let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")
private let papa = CoachSpeaker(id: "papa", name: "帕帕")

private func sideline(_ coach: CoachSpeaker = maotou, line day: LocalDay? = tuesday) -> SidelineCoach {
    SidelineCoach(
        coach: coach,
        note: day.map { CoachNote(day: $0, text: "全队今天拉伸。", coach: coach, writtenAt: morning, timeZone: newYork) })
}

private func note(from coach: CoachSpeaker = maotou) -> CoachMemberNote {
    CoachMemberNote(id: 7, squad: squad, day: tuesday, text: "昨天腿练狠了，今天别上重量。", coach: coach)
}

private func challenge(_ answer: CoachChallengeAnswer?, done: CoachChallengeCompleter? = nil) -> DayChallenge {
    DayChallenge(
        note: "7", day: tuesday,
        challenge: .init(title: "拉伸", amount: 20, unit: "分钟", answer: answer, completedBy: done))
}

@Test func myMorningNoteComesBeforeTheSquadsLine() {
    let face = CoachFace(
        squad: squad, coach: sideline(), morningNote: note(), challenge: nil, hasNews: true, at: morning)
    #expect(face.line == "昨天腿练狠了，今天别上重量。")
    #expect(face.hasNews)
    let noNote = CoachFace(
        squad: squad, coach: sideline(), morningNote: nil, challenge: nil, hasNews: false, at: morning)
    #expect(noNote.line == "全队今天拉伸。")
}

@Test func anotherCoachsNoteOrYesterdaysLineIsLeftOut() {
    let yesterday = sideline(line: tuesday.adding(days: -1))
    let face = CoachFace(
        squad: squad, coach: yesterday, morningNote: note(from: papa), challenge: nil, hasNews: false, at: morning)
    #expect(face.line == nil)
}

@Test func theChallengeButtonFollowsItsAnswer() {
    func step(_ day: DayChallenge) -> ChallengeStep? {
        CoachFace(squad: squad, coach: sideline(), morningNote: nil, challenge: day, hasNews: false, at: morning)
            .challenge?.step
    }
    #expect(step(challenge(nil)) == .open)
    #expect(step(challenge(.accepted)) == .accepted)
    #expect(step(challenge(.accepted, done: .coach)) == .done)
    #expect(step(challenge(.declined)) == nil)
    let face = CoachFace(
        squad: squad, coach: sideline(), morningNote: nil, challenge: challenge(nil), hasNews: false, at: morning)
    #expect(face.challenge?.title == "拉伸 20 分钟")
    #expect(face.challenge?.note == "7")
}
