import CheckInDomain
import Contracts
import Foundation
import Testing

private let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")
private let other = CoachSpeaker(id: "laowang", name: "老王")

private func note(_ day: String, by coach: CoachSpeaker = maotou) throws -> CoachNote {
    CoachNote(day: try LocalDay(day), text: "今天随缘，来了就算", coach: coach, writtenAt: Date(timeIntervalSince1970: 0))
}

/// 2026-11-03 09:00 in New York.
private let newYorkMorning = Date(timeIntervalSince1970: 1_793_714_400)

@Test func theCoachSaysItsLineWhileItsNewYorkDayLasts() throws {
    let coach = SidelineCoach(coach: maotou, note: try note("2026-11-03"))
    #expect(coach.line(at: newYorkMorning)?.text == "今天随缘，来了就算")
    // Until midnight in New York, then it is gone.
    #expect(coach.line(at: newYorkMorning.addingTimeInterval(14 * 3600)) != nil)
    #expect(coach.line(at: newYorkMorning.addingTimeInterval(16 * 3600)) == nil)
    #expect(SidelineCoach(coach: maotou, note: try note("2026-11-02")).line(at: newYorkMorning) == nil)
}

@Test func aLineFromACoachTheSquadFiredIsntPutInTheNewOnesMouth() throws {
    let coach = SidelineCoach(coach: maotou, note: try note("2026-11-03", by: other))
    #expect(coach.note == nil)
    #expect(coach.line(at: newYorkMorning) == nil)
}

@MainActor @Test func loadsTheSquadsCoachAndKeepsItWhenOffline() async throws {
    let backend = ScriptedBackend()
    let hired = SidelineCoach(coach: maotou, note: nil)
    await backend.set(coach: hired)
    let today = store(backend)
    await today.load()
    #expect(today.coach == hired)
    await backend.set(failure: .notSent)
    await today.load()
    #expect(today.coach == hired)
}

@MainActor @Test func showsNoCoachWhileTheSquadHasNone() async {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    #expect(today.coach == nil)
    #expect(today.coachLine == nil)
}

@MainActor @Test func theSidelineIsOpenForHireOnlyOnceTheSquadIsKnownToHaveNoCoach() async {
    let backend = ScriptedBackend(server: sampleHome())
    await backend.set(failure: .notSent)
    let today = store(backend)
    await today.load()
    // Not known yet: no empty spot, as the squad may have a coach.
    #expect(!today.isHiringCoach)
    await backend.set(failure: nil)
    await today.load()
    #expect(today.isHiringCoach)
    await backend.set(coach: SidelineCoach(coach: maotou, note: nil))
    await today.loadCoach()
    #expect(!today.isHiringCoach)
}

private func memberNote(_ id: Int, in squad: SquadID, _ text: String) throws -> CoachMemberNote {
    CoachMemberNote(id: id, squad: squad, day: try LocalDay("2026-11-03"), text: text, coach: maotou)
}

@MainActor @Test func showsTheMorningNoteOnlyWhenOpenedUntilPutAway() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    // A squad the member isn't in is never asked.
    await backend.set(notes: [
        try memberNote(1, in: squadID, "今天练力量"), try memberNote(3, in: SquadID(UUID()), "不是我的队"),
    ])
    let today = store(backend)
    await today.load()
    // Waiting, it doesn't show by itself: the coach's phone shows its dot.
    #expect(today.coachNotes.map(\.id) == [1])
    #expect(today.coachNote == nil)
    #expect(today.hasWaitingNote)
    // A tap on the coach or its push opens it, and the dot goes while it is open.
    today.showWaitingNote()
    #expect(today.coachNote?.text == "今天练力量")
    #expect(!today.hasWaitingNote)
    await today.putAwayNote()
    #expect(today.coachNote == nil)
    #expect(!today.hasWaitingNote)
    #expect(await backend.putAway == [1])
    // Loaded again, a put-away note stays away.
    await today.load()
    #expect(today.coachNote == nil)

    // Shown again from 通知, it comes back until it is put away again.
    let again = try memberNote(1, in: squadID, "今天练力量")
    today.showAgain(again)
    #expect(today.coachNote == again)
    await today.putAwayNote()
    #expect(today.coachNote == nil)
}

@MainActor @Test func aPushTappedForANoteAlreadyGoneOpensNoLaterOne() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    // Its note was put away on another phone before this one loaded.
    today.showWaitingNote()
    await today.load()
    #expect(today.coachNote == nil)
    // Tomorrow's note waits on the coach's phone instead of opening by itself.
    await backend.set(notes: [try memberNote(2, in: squadID, "明天慢跑")])
    await today.load()
    #expect(today.coachNote == nil)
    #expect(today.hasWaitingNote)
}

@MainActor @Test func aNotePutAwayOfflineStaysAwayOnThisPhone() async throws {
    let backend = ScriptedBackend()
    await backend.set(notes: [try memberNote(1, in: squadID, "今天练力量")])
    let today = store(backend)
    await today.load()
    today.showWaitingNote()
    await backend.set(failure: .notSent)
    await today.putAwayNote()
    await backend.set(failure: nil)
    await today.load()
    #expect(today.coachNote == nil)
    #expect(await backend.putAway == [])
}

@MainActor @Test func theCoachsCardOpensTodaysNoteAgainOnceItWasPutAway() async throws {
    let backend = ScriptedBackend()
    await backend.set(notes: [try memberNote(1, in: squadID, "今天练力量")])
    let today = store(backend, now: newYorkMorning)
    await today.load()
    // While it waits, a tap on the coach opens it, so the card offers nothing.
    #expect(today.todaysNote == nil)
    today.showWaitingNote()
    #expect(today.todaysNote == nil)
    await today.putAwayNote()
    #expect(today.todaysNote?.text == "今天练力量")
    // On a new launch, the phone still has it for the rest of its day, then it is gone.
    let relaunched = store(backend, now: newYorkMorning.addingTimeInterval(3600))
    await relaunched.load()
    #expect(relaunched.todaysNote?.id == 1)
    let tomorrow = store(backend, now: newYorkMorning.addingTimeInterval(24 * 3600))
    await tomorrow.load()
    #expect(tomorrow.todaysNote == nil)
}
