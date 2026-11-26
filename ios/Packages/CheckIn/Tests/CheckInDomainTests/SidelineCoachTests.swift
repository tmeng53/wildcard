import CheckInDomain
import Contracts
import Foundation
import Testing

private let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")
private let other = CoachSpeaker(id: "laowang", name: "老王")

private func note(_ day: String, by coach: CoachSpeaker = maotou) throws -> CoachNote {
    CoachNote(
        day: try LocalDay(day), text: "今天随缘，来了就算", coach: coach, writtenAt: Date(timeIntervalSince1970: 0),
        timeZone: SquadTimeZone.newYorkClock)
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

@MainActor @Test func theNewestUnseenCardOnTheCoachsPageShowsUntilSeen() async {
    let backend = ScriptedBackend(server: sampleHome())
    let today = store(backend)
    await today.load()
    #expect(!today.hasUnseenCoachCards)
    #expect(today.newestUnseenCoachCard == nil)
    let note = CoachPageCard(
        kind: .note, id: "41", coach: maotou, look: "xiaohun", time: Date(timeIntervalSince1970: 1_000),
        text: "今天腿还酸吗")
    await backend.set(unseenCoachCard: note)
    await today.load()
    #expect(today.hasUnseenCoachCards)
    #expect(today.newestUnseenCoachCard?.text == "今天腿还酸吗")
    // What was shown stays while the server can't be reached.
    await backend.set(failure: .notSent)
    await today.loadCoach()
    #expect(today.newestUnseenCoachCard?.id == "41")
    // Swiped away on the coach's page, the server marks them seen; the next load takes it away.
    await backend.set(failure: nil)
    await backend.set(unseenCoachCard: nil)
    await today.load()
    #expect(!today.hasUnseenCoachCards)
    #expect(today.newestUnseenCoachCard == nil)
}

@MainActor @Test func aBoxedGiftShowsUntilItIsOpened() async {
    let backend = ScriptedBackend(server: sampleHome())
    let today = store(backend)
    await today.load()
    #expect(today.unopenedCoachGift == nil)
    let gift = CoachPageCard(
        kind: .gift, id: "gift-sheeptowel", coach: maotou, look: "xiaohun", time: Date(timeIntervalSince1970: 1_000),
        gift: CoachPageCard.Gift(piece: "gift-sheeptowel"))
    await backend.set(unopenedGift: gift)
    await today.load()
    #expect(today.unopenedCoachGift?.id == "gift-sheeptowel")
    // What was shown stays while the server can't be reached.
    await backend.set(failure: .notSent)
    await today.loadCoach()
    #expect(today.unopenedCoachGift?.id == "gift-sheeptowel")
    // Opened on the coach's page, the next load takes it away.
    await backend.set(failure: nil)
    await backend.set(unopenedGift: nil)
    await today.loadCoach()
    #expect(today.unopenedCoachGift == nil)
}

@MainActor @Test func theCoachKeptOnThePhoneStandsOnTheSidelineWhileTheServerCantBeReached() async throws {
    let home = sampleHome()
    let backend = ScriptedBackend(saved: home, server: home)
    await backend.set(keptCoach: SavedCoach(squad: home.squad.id, coach: maotou))
    await backend.set(failure: .notSent)
    let today = store(backend)
    await today.load()
    #expect(today.coach == SidelineCoach(coach: maotou, note: nil))
    // Its line isn't kept: only the server's load brings it.
    #expect(today.coachLine == nil)
    // The server's word wins once it answers.
    await backend.set(failure: nil)
    await backend.set(coach: SidelineCoach(coach: other, note: nil))
    await today.load()
    #expect(today.coach?.coach == other)
}

@MainActor @Test func aCoachKeptForAnotherSquadIsntShown() async throws {
    let home = sampleHome()
    let backend = ScriptedBackend(saved: home, server: home)
    await backend.set(keptCoach: SavedCoach(squad: SquadID(UUID()), coach: maotou))
    await backend.set(failure: .notSent)
    let today = store(backend)
    await today.load()
    #expect(today.coach == nil)
    #expect(!today.isHiringCoach)
}

@MainActor @Test func aSquadKeptWithNoCoachLeavesTheSidelineOpenForHire() async throws {
    let home = sampleHome()
    let backend = ScriptedBackend(saved: home, server: home)
    await backend.set(keptCoach: SavedCoach(squad: home.squad.id, coach: nil))
    await backend.set(failure: .notSent)
    let today = store(backend)
    await today.load()
    #expect(today.isHiringCoach)
}
