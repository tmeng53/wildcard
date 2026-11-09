import CheckInDomain
import Contracts
import Foundation
import Testing

private let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")
private let papa = CoachSpeaker(id: "papa", name: "帕帕")

private func letter(_ id: Int = 4, to coach: CoachSpeaker = papa) throws -> CoachLetter {
    CoachLetter(
        id: id, squad: squadID, from: maotou, to: coach, day: try LocalDay("2026-11-03"), text: "这队交给你了，我先撤。")
}

@MainActor @Test func theOldCoachWritesUntilTheLetterIsDoneThenTheCoachesSwapAndItOpensSealed() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    await backend.set(coach: SidelineCoach(coach: maotou, note: nil))
    await backend.set(letter: try letter(), holds: true)
    let today = store(backend)
    await today.load()

    #expect(today.beginHandover(from: maotou, to: papa))
    let swap = Task { await today.writeLetter() }
    while await backend.lettersAsked == 0 { await Task.yield() }
    // Writing, however long it takes: no letter yet, and the coaches haven't swapped.
    #expect(today.handover?.end == nil)
    #expect(today.letter == nil)
    #expect(today.coach?.coach == maotou)

    await backend.releaseLetter()
    await swap.value
    #expect(today.handover?.end == tuesdayMorning)
    #expect(today.letter == ShownLetter(letter: try letter(), isSealed: true))
    // Played out, the new coach stands on the sideline with its letter.
    today.finishHandover()
    #expect(today.handover == nil)
    #expect(today.coach == SidelineCoach(coach: papa, note: nil, letter: try letter()))
    #expect(today.coachLetter == (try letter()))

    await today.putAwayLetter()
    #expect(today.letter == nil)
    #expect(await backend.openedLetter() == 4)
}

/// The app reads the squad's coach again as soon as 换教练 lands, before the letter is written,
/// so the new coach may already stand without it: it still gets the letter once the swap ends.
@MainActor @Test func aCoachReadAgainDuringTheSwapStillGetsItsLetter() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    await backend.set(coach: SidelineCoach(coach: maotou, note: nil))
    await backend.set(letter: try letter(), holds: true)
    let today = store(backend)
    await today.load()
    today.beginHandover(from: maotou, to: papa)
    let swap = Task { await today.writeLetter() }
    while await backend.lettersAsked == 0 { await Task.yield() }
    await backend.set(coach: SidelineCoach(coach: papa, note: nil))
    await today.loadCoach()
    await backend.releaseLetter()
    await swap.value
    today.finishHandover()
    #expect(today.coach == SidelineCoach(coach: papa, note: nil, letter: try letter()))
    #expect(today.letter == ShownLetter(letter: try letter(), isSealed: true))
}

@MainActor @Test func aLetterThatCouldntBeWrittenSwapsTheCoachesWithoutOne() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    await backend.set(coach: SidelineCoach(coach: maotou, note: nil))
    await backend.set(letter: nil)
    let today = store(backend)
    await today.load()
    today.beginHandover(from: maotou, to: papa)
    await today.writeLetter()
    #expect(today.handover?.end == tuesdayMorning)
    #expect(today.handover?.letter == nil)
    #expect(today.letter == nil)
    today.finishHandover()
    #expect(today.coach?.coach == papa)

    // Nor does one that failed to arrive.
    await backend.set(coach: SidelineCoach(coach: papa, note: nil))
    await backend.set(letter: try letter(to: maotou))
    await today.load()
    await backend.set(failure: .notSent)
    today.beginHandover(from: papa, to: maotou)
    await today.writeLetter()
    #expect(today.handover?.end != nil)
    #expect(today.handover?.letter == nil)
}

@MainActor @Test func everyMemberOpensANewLetterOnceOnEachPhone() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    await backend.set(coach: SidelineCoach(coach: papa, note: nil, letter: try letter()))
    let today = store(backend)
    await today.load()
    #expect(today.letter == ShownLetter(letter: try letter(), isSealed: true))
    await today.putAwayLetter()
    #expect(today.letter == nil)

    // This phone opened it: the next launch doesn't open it again.
    let relaunched = store(backend)
    await relaunched.load()
    #expect(relaunched.letter == nil)
    #expect(relaunched.coachLetter == (try letter()))

    // 通知 and the 简历 open it again, unsealed, without telling the phone anything new.
    relaunched.showAgain(try letter())
    #expect(relaunched.letter == ShownLetter(letter: try letter(), isSealed: false))
    await relaunched.putAwayLetter()
    #expect(relaunched.letter == nil)
}

@MainActor @Test func aNewLetterReadFirstFromNoticesIsntSealedOnTodayAfter() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    await backend.set(coach: SidelineCoach(coach: papa, note: nil, letter: try letter()))
    let today = store(backend)
    await today.load()
    today.showAgain(try letter())
    #expect(today.letter == ShownLetter(letter: try letter(), isSealed: false))
    await today.putAwayLetter()
    #expect(today.letter == nil)

    let relaunched = store(backend)
    await relaunched.load()
    #expect(relaunched.letter == nil)
}

@Test func aLetterToAnotherCoachIsntTheSquadsCoachs() throws {
    #expect(SidelineCoach(coach: maotou, note: nil, letter: try letter(to: papa)).letter == nil)
    #expect(SidelineCoach(coach: papa, note: nil, letter: try letter(to: papa)).letter == (try letter()))
}

private let start = Date(timeIntervalSince1970: 1_000)
private let sideline = StagePoint(x: 60, y: 690)

@Test func theNewCoachWalksInAndWaitsBesideTheSideline() {
    let handover = CoachHandover(from: maotou, to: papa, start: start)
    // Off the left edge, then beside the spot once it has walked in, while the old coach writes.
    #expect(handover.incoming(at: start, sideline: sideline) == -110)
    #expect(handover.incoming(at: start.addingTimeInterval(1.7), sideline: sideline) == 61)
    #expect(handover.incoming(at: start.addingTimeInterval(60), sideline: sideline) == 61)
    #expect(handover.chip(at: start.addingTimeInterval(0.9)) == 0)
    #expect(handover.chip(at: start.addingTimeInterval(1.2)) == 1)
    #expect(handover.outgoing(at: start.addingTimeInterval(60)) == (0, 0))
    #expect(handover.showsOutgoing(at: start.addingTimeInterval(60)))
    #expect(handover.leavesAt == nil)
    #expect(handover.finishesAt == nil)
}

@Test func onceTheLetterIsDoneTheOldCoachWalksOffAndTheNewOneStepsIn() throws {
    var handover = CoachHandover(from: maotou, to: papa, start: start)
    let done = start.addingTimeInterval(5)
    handover.end(at: done, letter: try letter())
    #expect(handover.leavesAt == done)
    #expect(handover.envelopeAt == done.addingTimeInterval(0.1))
    #expect(close(handover.chip(at: done.addingTimeInterval(0.3)), 0))
    // A hop, a step, another hop, each eased on its own, as the prototype's keyframes play.
    let hop = handover.outgoing(at: done.addingTimeInterval(0.26))
    #expect(close(hop.dx, 0) && close(hop.lift, 6 * 390 / 340))
    #expect(close(handover.outgoing(at: done.addingTimeInterval(0.52)).dx, -30 * 390 / 340))
    #expect(close(handover.outgoing(at: done.addingTimeInterval(0.78)).dx, -60 * 390 / 340))
    // Off the left edge by its 140 prototype pixels.
    #expect(close(handover.outgoing(at: done.addingTimeInterval(1.3)).dx, -140 * 390 / 340))
    #expect(!handover.showsOutgoing(at: done.addingTimeInterval(1.31)))
    #expect(handover.incoming(at: done.addingTimeInterval(1), sideline: sideline) == 61)
    #expect(close(handover.incoming(at: done.addingTimeInterval(1.8), sideline: sideline), 0))
    #expect(close(handover.finishesAt?.timeIntervalSince(done) ?? 0, 1.8))
    // Ended again, it stays as it ended.
    handover.end(at: done.addingTimeInterval(9), letter: nil)
    #expect(handover.letter == (try letter()))
}

@Test func aLetterWrittenAtOnceStillLetsTheNewCoachWalkInFirst() {
    var handover = CoachHandover(from: maotou, to: papa, start: start)
    handover.end(at: start.addingTimeInterval(0.1), letter: nil)
    // The old coach starts off once it began writing, and the new one steps in once it has walked in.
    #expect(handover.leavesAt == start.addingTimeInterval(0.9))
    #expect(handover.envelopeAt == nil)
    #expect(handover.incoming(at: start.addingTimeInterval(1.7), sideline: sideline) == 61)
    #expect(close(handover.finishesAt?.timeIntervalSince(start) ?? 0, 2.7))
}

private func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.001 }

@Test func theSealOpensOnlyOnceTheEnvelopeHasLanded() {
    var opening = LetterOpening(shown: start)
    #expect(opening.flight(at: start) == 0)
    #expect(opening.showsEnvelope(at: start.addingTimeInterval(60)))
    #expect(opening.flight(at: start.addingTimeInterval(0.75)) == 1)
    #expect(close(opening.scrim(at: start.addingTimeInterval(0.4)), 1))
    opening.open(at: start.addingTimeInterval(0.5))
    #expect(opening.opened == nil)
    // Settled, it pulses until tapped.
    #expect(opening.seal(at: start.addingTimeInterval(0.85)) == (1, 1))
    #expect(close(opening.seal(at: start.addingTimeInterval(1.4)).scale, 1.08))
    let tap = start.addingTimeInterval(2)
    opening.open(at: tap)
    #expect(opening.opened == tap)
    opening.open(at: tap.addingTimeInterval(1))
    #expect(opening.opened == tap)
}

@Test func theLetterComesOutAndUnfoldsByThePrototypesBeats() {
    let tap = start.addingTimeInterval(2)
    let opening = LetterOpening(shown: start, opened: tap)
    func at(_ seconds: Double) -> Date { tap.addingTimeInterval(seconds) }
    #expect(close(opening.seal(at: at(0.25)).scale, 1.25))
    #expect(close(opening.seal(at: at(0.25)).opacity, 0))
    #expect(close(opening.frontFlap(at: at(0.2)) ?? -1, 0))
    #expect(opening.frontFlap(at: at(0.46)) == 90)
    #expect(opening.frontFlap(at: at(0.47)) == nil)
    #expect(opening.backFlap(at: at(0.46)) == nil)
    #expect(close(opening.backFlap(at: at(0.77)) ?? 0, 180))
    #expect(!opening.showsLetter(at: at(0.46)))
    #expect(opening.showsLetter(at: at(0.47)))
    #expect(close(opening.rise(at: at(1.5)), 1))
    #expect(opening.clipsLetter(at: at(1.49)))
    #expect(!opening.clipsLetter(at: at(1.5)))
    #expect(close(opening.drop(at: at(2.06)), 1))
    #expect(opening.showsEnvelope(at: at(2.05)))
    #expect(!opening.showsEnvelope(at: at(2.07)))
    #expect(close(opening.unfold(at: at(2.33)).place, 1))
    #expect(close(opening.unfold(at: at(2.4)).height, 1))
    #expect(close(opening.button(at: at(2.08)), 0))
    #expect(close(opening.button(at: at(2.39)), 1))
    #expect(!opening.isOpen(at: at(2.37)))
    #expect(opening.isOpen(at: at(2.39)))
}
