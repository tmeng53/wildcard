import CheckInDomain
import Contracts
import Foundation
import Testing

private let run = CheckInDraft.trained(.sport("run"), nil, PostBody(photos: [], caption: "雨中五公里"))

@MainActor @Test func aMemberWhoTravelledTakesThePhonesZoneOnlyOnceTheirWaitingPostsAreOut() async throws {
    // A post made offline keeps the day it was made on in the old zone, which the server checks
    // against the profile's zone, so the zone moves only after it has gone out.
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    #expect(await backend.savesWhenZoneFollowed == [0])
    #expect(await backend.homeLoads == 1)

    await backend.set(failure: .notSent)
    #expect(try await today.post(run) == .queued)
    await backend.set(failure: nil)
    await backend.set(phoneZoneMoved: true)
    await today.load()
    #expect(today.pending.isEmpty)
    #expect(await backend.savesWhenZoneFollowed == [0, 1])
    // The zone moved, so the home is read again in it.
    #expect(await backend.homeLoads == 3)

    await today.load()
    #expect(await backend.homeLoads == 4)
}
