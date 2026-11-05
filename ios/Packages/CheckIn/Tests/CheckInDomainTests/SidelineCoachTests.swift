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
    // Until 3am the next morning in New York, then it is gone.
    #expect(coach.line(at: newYorkMorning.addingTimeInterval(17 * 3600)) != nil)
    #expect(coach.line(at: newYorkMorning.addingTimeInterval(19 * 3600)) == nil)
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

private func memberNote(_ id: Int, in squad: SquadID, _ text: String) throws -> CoachMemberNote {
    CoachMemberNote(id: id, squad: squad, day: try LocalDay("2026-11-03"), text: text, coach: maotou)
}

@MainActor @Test func showsEachSquadsMorningNoteOneAfterAnotherUntilPutAway() async throws {
    let other = SquadID(UUID())
    let home = sampleHome()
    let twoSquads = Home(
        member: home.member, timeZone: home.timeZone, squad: home.squad,
        squads: [Squad(id: other, name: "另一队", inviteCode: "A2B3C4D5", members: [myID], captain: myID), home.squad],
        today: home.today, plan: home.plan, checkIns: [])
    let backend = ScriptedBackend(server: twoSquads)
    // The other squad's coach wrote too; a squad the member isn't in is never asked.
    await backend.set(notes: [
        try memberNote(2, in: other, "另一队的便条"), try memberNote(1, in: squadID, "今天练力量"),
        try memberNote(3, in: SquadID(UUID()), "不是我的队"),
    ])
    let today = store(backend)
    await today.load()
    // The home's own squad's note first.
    #expect(today.coachNote?.text == "今天练力量")
    await today.putAwayNote()
    #expect(today.coachNote?.text == "另一队的便条")
    await today.putAwayNote()
    #expect(today.coachNote == nil)
    #expect(await backend.putAway == [1, 2])
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

@MainActor @Test func aNotePutAwayOfflineStaysAwayOnThisPhone() async throws {
    let backend = ScriptedBackend()
    await backend.set(notes: [try memberNote(1, in: squadID, "今天练力量")])
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)
    await today.putAwayNote()
    await backend.set(failure: nil)
    await today.load()
    #expect(today.coachNote == nil)
    #expect(await backend.putAway == [])
}
