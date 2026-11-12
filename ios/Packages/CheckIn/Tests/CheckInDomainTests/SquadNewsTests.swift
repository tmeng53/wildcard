import CheckInDomain
import Contracts
import Foundation
import Testing

private let newcomer = MemberID(id(4))

private func home(members: [MemberID], captain: MemberID, squad: SquadID = squadID) -> Home {
    let sample = sampleHome()
    return Home(
        member: myID, timeZone: sample.timeZone,
        squad: Squad(id: squad, name: "周三不练腿", inviteCode: "K7M2QX9P", members: members, captain: captain),
        today: sample.today, plan: sample.plan, checkIns: [])
}

@MainActor @Test func aTeammateWhoJoinedSinceTheKeptHomeIsToldOnce() async {
    let kept = home(members: [mate, myID, resting], captain: mate)
    let backend = ScriptedBackend(saved: kept, server: home(members: [mate, myID, resting, newcomer], captain: mate))
    let today = store(backend)

    await today.load()
    #expect(today.takeNews() == SquadNews(joined: [newcomer]))
    #expect(today.takeNews() == SquadNews())

    await today.refresh()
    #expect(today.takeNews() == SquadNews())
}

@MainActor @Test func aHandoverToTheMemberIsToldOnceAndALeaveSaysNothing() async {
    let kept = home(members: [mate, myID, resting], captain: mate)
    let backend = ScriptedBackend(saved: kept, server: home(members: [myID, resting], captain: myID))
    let today = store(backend)

    await today.load()
    #expect(today.takeNews() == SquadNews(madeCaptain: true))
    #expect(today.takeNews() == SquadNews())
}

@MainActor @Test func newsNotYetToldAddsUp() async {
    let backend = ScriptedBackend(
        saved: home(members: [mate, myID], captain: mate), server: home(members: [mate, myID, resting], captain: mate))
    let today = store(backend)
    await today.load()

    await backend.set(server: home(members: [mate, myID, resting, newcomer], captain: myID))
    await today.refresh()
    #expect(today.takeNews() == SquadNews(joined: [resting, newcomer], madeCaptain: true))
}

@MainActor @Test func aFirstHomeOrAnotherSquadsTellsNothing() async {
    let first = store(ScriptedBackend(saved: nil, server: home(members: [mate, myID, newcomer], captain: myID)))
    await first.load()
    #expect(first.takeNews() == SquadNews())

    let moved = store(
        ScriptedBackend(
            saved: home(members: [mate, myID], captain: mate),
            server: home(members: [newcomer, myID], captain: myID, squad: SquadID(id(11)))))
    await moved.load()
    #expect(moved.takeNews() == SquadNews())
}

@MainActor @Test func aMemberNoLongerInTheSquadHasNoHome() async {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    #expect(today.phase == .current)

    await backend.set(server: nil)
    await today.refresh()
    #expect(today.phase == .noSquad)
    #expect(today.home == nil)
}
