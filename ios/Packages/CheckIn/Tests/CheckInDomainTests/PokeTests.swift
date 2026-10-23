import CheckInDomain
import Contracts
import Foundation
import Testing

@MainActor @Test func loadsWhomIPattedAndWhoPattedMe() async {
    let backend = ScriptedBackend()
    let received = ReceivedPoke(from: mate, patAt: Timestamp(millisecondsSince1970: 1_792_500_000_000))
    await backend.set(pokes: SquadPokes(sent: [resting], received: [received]))
    let today = store(backend)
    await today.load()
    #expect(today.pokes == SquadPokes(sent: [resting], received: [received]))
    #expect(today.canPat(mate))
    #expect(!today.canPat(resting))
    #expect(!today.canPat(myID))
    #expect(!today.canPat(MemberID(id(99))))
}

@MainActor @Test func patsATeammateOnceADay() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    try await today.pat(mate)
    try await today.pat(mate)
    #expect(await backend.pats == [mate])
    #expect(today.pokes.sent == [mate])
    #expect(!today.canPat(mate))
}

@MainActor @Test func takesAPatBackWhenItDoesNotGoOut() async {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)
    await #expect(throws: CheckInError.notSent) { try await today.pat(mate) }
    #expect(today.pokes.sent == [])
    #expect(today.canPat(mate))
}

@MainActor @Test func keepsThePokesShownWhenOffline() async {
    let backend = ScriptedBackend()
    await backend.set(pokes: SquadPokes(sent: [mate], received: []))
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)
    await today.load()
    #expect(today.pokes.sent == [mate])
}
