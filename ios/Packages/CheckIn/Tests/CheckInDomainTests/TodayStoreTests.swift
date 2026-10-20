import CheckInDomain
import Contracts
import Foundation
import Testing

private let run = CheckInDraft.trained(.sport(.run), PostBody(photos: [], caption: "雨中五公里"))

@MainActor @Test func opensOnTheSavedCopyThenTheServers() async throws {
    var stale = sampleHome()
    stale.today.squadWeek = WeekCount(trainedDays: 9, plannedDays: 22)
    let backend = ScriptedBackend(saved: stale)
    await backend.set(failure: .notSent)
    let today = store(backend)

    await today.load()
    #expect(today.phase == .offline)
    #expect(today.home?.today.squadWeek == WeekCount(trainedDays: 9, plannedDays: 22))

    await backend.set(failure: nil)
    await today.load()
    #expect(today.phase == .current)
    #expect(today.home?.today.squadWeek == WeekCount(trainedDays: 14, plannedDays: 22))
}

@MainActor @Test func saysWhenTheMemberIsInNoSquadOrSignedOut() async {
    let today = store(ScriptedBackend(server: nil))
    await today.load()
    #expect(today.phase == .noSquad)
    #expect(today.home == nil)

    let signedOut = ScriptedBackend()
    await signedOut.set(failure: .signedOut)
    let other = store(signedOut)
    await other.load()
    #expect(other.phase == .signedOut)
}

@MainActor @Test func aFirstTrainingCountsOnceForTheSquadAndTheMember() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    let outcome = try await today.post(run)
    guard case .posted(let saved) = outcome else {
        Issue.record("expected posted, got \(outcome)")
        return
    }
    #expect(saved.id == CheckInID(id(100)))
    #expect(saved.member == myID)
    #expect(saved.day.description == "2026-10-20")
    #expect(saved.createdAt == Timestamp(millisecondsSince1970: 1_792_515_600_000))
    #expect(saved.audience.squads == [squadID])
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.squadWeek == WeekCount(trainedDays: 15, plannedDays: 22))
    #expect(today.home?.today.today.trained == 2)
    #expect(today.home?.today.myWeek.week == WeekCount(trainedDays: 2, plannedDays: 5))

    try await today.post(.trained(.sport(.yoga), PostBody(photos: [], caption: "")))
    #expect(today.home?.today.squadWeek == WeekCount(trainedDays: 15, plannedDays: 22))
    #expect(today.home?.today.today.trained == 2)
    #expect(await backend.saves.count == 2)
}

@MainActor @Test func offlineAPostWaitsCountedAndGoesOutOnceUnderItsID() async throws {
    let backend = ScriptedBackend()
    let outbox = MemoryOutbox()
    let today = store(backend, outbox: outbox)
    await today.load()
    await backend.set(failure: .notSent)

    #expect(try await today.post(run) == .queued)
    #expect(today.pending.map(\.id) == [CheckInID(id(100))])
    #expect(await outbox.kept.map(\.id) == [CheckInID(id(100))])
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.squadWeek.trainedDays == 15)

    await backend.set(failure: nil)
    await today.load()
    #expect(today.pending.isEmpty)
    #expect(await outbox.kept.isEmpty)
    #expect(await backend.saves.map(\.id) == [CheckInID(id(100))])
    // The server's count now has it; it isn't counted twice.
    #expect(today.home?.today.squadWeek.trainedDays == 15)
}

@MainActor @Test func aPostWaitingSurvivesTheAppClosing() async throws {
    let backend = ScriptedBackend()
    let outbox = MemoryOutbox()
    let first = store(backend, outbox: outbox)
    await first.load()
    await backend.set(failure: .notSent)
    try await first.post(.healthyMeal(PostBody(photos: [photo(1)], caption: "鸡胸肉")))

    let relaunched = store(ScriptedBackend(saved: sampleHome()), outbox: outbox)
    await relaunched.load()
    #expect(relaunched.pending.isEmpty)
    #expect(relaunched.home?.mine?.latestMeal == .healthyMeal)
}

@MainActor @Test func photosUploadedBeforeTheNetworkDroppedArentUploadedAgain() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(uploadsBeforeFailing: 1)

    let photos = [photo(3), photo(1), photo(2)]
    #expect(try await today.post(.trained(.sport(.climb), PostBody(photos: photos, caption: ""))) == .queued)
    #expect(today.pending.first?.uploaded.keys.sorted() == [id(3)])

    await backend.set(uploadsBeforeFailing: .max)
    await today.sendPending()
    #expect(await backend.uploads == [id(3), id(1), id(2)])
    let saved = try #require(await backend.saves.first)
    guard case .trained(let training) = saved.entry else {
        Issue.record("expected a 练了")
        return
    }
    // The cover stays first.
    #expect(training.photos?.all.map(\.path) == photos.map { "\(myID)/\($0.id.uuidString.lowercased())" })
}

@MainActor @Test func aDisclaimerIsOnceADayAndNeverAfterTraining() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)

    #expect(try await today.post(.disclaimer(try Disclaimer("加班到十点"))) == .queued)
    #expect(today.myStatus == .disclaimer)
    #expect(today.home?.today.today.disclaimer == 1)
    await #expect(throws: CheckInError.disclaimerAlreadyPosted) {
        try await today.post(.disclaimer(try Disclaimer("又加班")))
    }

    try await today.post(run)
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.today.disclaimer == 0)
    await #expect(throws: CheckInError.alreadyTrained) {
        try await today.post(.disclaimer(try Disclaimer("算了")))
    }
}

@MainActor @Test func aPostTheServerRefusesLaterIsDroppedAndSaid() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)
    try await today.post(run)

    await backend.set(failure: .outOfTime)
    await today.sendPending()
    #expect(today.pending.isEmpty)
    #expect(today.refused.map(\.reason) == [.outOfTime])
    #expect(today.myStatus == .notCheckedIn)
    today.dismissRefused()
    #expect(today.refused.isEmpty)
}

@MainActor @Test func aRefusalWhilePostingIsThrownAndNothingWaits() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notInSquad)
    await #expect(throws: CheckInError.notInSquad) { try await today.post(run) }
    #expect(today.pending.isEmpty)
    #expect(today.myStatus == .notCheckedIn)
}

@MainActor @Test func beforeThreeInTheMorningItIsStillYesterday() async throws {
    // Wednesday 02:30 in Los Angeles.
    let today = store(ScriptedBackend(), now: tuesdayMorning.addingTimeInterval(16.5 * 3600))
    await today.load()
    #expect(today.day?.description == "2026-10-20")
    guard case .posted(let saved) = try await today.post(run) else {
        Issue.record("expected posted")
        return
    }
    #expect(saved.day.description == "2026-10-20")
}

@MainActor @Test func aNewTrainingStartsWithTodaysPlannedSport() async {
    let today = store(ScriptedBackend())
    #expect(today.suggestedActivity == nil)
    await today.load()
    #expect(today.suggestedActivity == .sport(.yoga))
}

@MainActor @Test func reactionsShowAtOnceAndComeBackOnFailure() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    let checkIn = CheckInID(id(50))

    try await today.react(.lol, to: checkIn)
    #expect(today.myReaction(on: checkIn) == .lol)

    await backend.set(failure: .notSent)
    await #expect(throws: CheckInError.notSent) { try await today.react(.cheer, to: checkIn) }
    #expect(today.myReaction(on: checkIn) == .lol)
    await #expect(throws: CheckInError.notSent) { try await today.removeReaction(from: checkIn) }
    #expect(today.myReaction(on: checkIn) == .lol)

    await backend.set(failure: nil)
    try await today.removeReaction(from: checkIn)
    #expect(today.myReaction(on: checkIn) == nil)
    try await today.loadReactions(to: checkIn)
    #expect(today.reactions[checkIn] == [])
}
