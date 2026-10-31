import CheckInDomain
import Contracts
import Foundation
import Testing

private let run = CheckInDraft.trained(.sport("run"), nil, PostBody(photos: [], caption: "雨中五公里"))

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

    try await today.post(.trained(.sport("yoga"), nil, PostBody(photos: [], caption: "")))
    #expect(today.home?.today.squadWeek == WeekCount(trainedDays: 15, plannedDays: 22))
    #expect(today.home?.today.today.trained == 2)
    #expect(await backend.saves.count == 2)
}

@MainActor @Test func aPostSharedToNoSquadCountsOnlyForTheMember() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    let outcome = try await today.post(run, sharedTo: [])
    guard case .posted(let saved) = outcome else {
        Issue.record("expected posted, got \(outcome)")
        return
    }
    #expect(saved.audience.squads == [])
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.myWeek.week == WeekCount(trainedDays: 2, plannedDays: 5))
    #expect(today.home?.today.today.trained == 1)
    #expect(today.home?.today.squadWeek == WeekCount(trainedDays: 14, plannedDays: 22))
    // A 请假条 after it is refused at once, as the server would.
    await #expect(throws: CheckInError.alreadyTrained) {
        try await today.post(.disclaimer(try Disclaimer("累")), sharedTo: [])
    }
}

@MainActor @Test func aSharedTrainingAfterAPrivateDisclaimerCountsWhatTheSquadSaw() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    _ = try await today.post(.disclaimer(try Disclaimer("累")), sharedTo: [])
    _ = try await today.post(run)
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.today == TodayCounts(trained: 2, disclaimer: 0, resting: 1, everyoneTrained: true))
    #expect(today.home?.today.squadWeek == WeekCount(trainedDays: 15, plannedDays: 22))
    #expect(today.home?.today.myWeek.week == WeekCount(trainedDays: 2, plannedDays: 5))
}

@MainActor @Test func waitingPostsCountWhatTheSquadSees() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)

    #expect(try await today.post(run, sharedTo: []) == .queued)
    #expect(today.home?.today.squadWeek.trainedDays == 14)
    #expect(today.home?.today.today.everyoneTrained == false)
    #expect(try await today.post(run) == .queued)
    #expect(today.home?.today.today.trained == 2)
    #expect(today.home?.today.squadWeek.trainedDays == 15)
    #expect(today.home?.today.myWeek.week.trainedDays == 2)
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
    #expect(try await today.post(.trained(.sport("climb"), nil, PostBody(photos: photos, caption: ""))) == .queued)
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
    // Each photo's size goes with it, even for the one uploaded before the network dropped.
    #expect(training.photos?.all.map(\.size) == Array(repeating: try PhotoSize(width: 1080, height: 1350), count: 3))
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
    #expect(today.suggestedActivity == .sport("yoga"))
}

@MainActor @Test func reactionsShowAtOnceAndComeBackOnFailure() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    let checkIn = CheckInID(id(50))
    let laughing = try Emoji("😂")

    try await today.react(laughing, to: checkIn)
    #expect(today.myReaction(on: checkIn) == laughing)

    await backend.set(failure: .notSent)
    await #expect(throws: CheckInError.notSent) { try await today.react(.heart, to: checkIn) }
    #expect(today.myReaction(on: checkIn) == laughing)
    await #expect(throws: CheckInError.notSent) { try await today.removeReaction(from: checkIn) }
    #expect(today.myReaction(on: checkIn) == laughing)

    await backend.set(failure: nil)
    try await today.removeReaction(from: checkIn)
    #expect(today.myReaction(on: checkIn) == nil)
    try await today.loadReactions(to: checkIn)
    #expect(today.reactions[checkIn] == [])
}

@MainActor @Test func onANewDayTheHomeKeptFromYesterdayStartsTheMemberAfresh() async throws {
    // Tuesday's copy, opened offline on Wednesday at 10:00.
    var yesterday = sampleToday()
    yesterday.members[1] = entry(myID, .trained, since: 1_792_512_000_000)
    yesterday.today.trained = 2
    let backend = ScriptedBackend(saved: sampleHome(today: yesterday))
    await backend.set(failure: .notSent)
    let today = store(backend, now: tuesdayMorning.addingTimeInterval(24 * 3600))
    await today.load()

    #expect(today.day?.description == "2026-10-21")
    #expect(today.myStatus == .notCheckedIn)
    #expect(today.home?.mine?.day.description == "2026-10-21")
    #expect(today.home?.today.today.trained == 1)

    #expect(try await today.post(run) == .queued)
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.today.trained == 2)
    #expect(today.home?.today.squadWeek.trainedDays == 15)
    await #expect(throws: CheckInError.alreadyTrained) {
        try await today.post(.disclaimer(try Disclaimer("加班")))
    }
}

@MainActor @Test func aPostSavedWhileTheHomeLoadedIsStillCounted() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    try await today.post(run)

    // A load that read the server before the post was saved.
    await backend.set(server: sampleHome())
    await today.refresh()
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.squadWeek.trainedDays == 15)
    #expect(today.home?.todaysSport(of: myID) == .sport("run"))
}

@MainActor @Test func aDisclaimerAsksTheServerFirstForATrainingFromAnotherPhone() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    // The member trains on another phone after this one loaded.
    var trained = sampleToday()
    trained.members[1] = entry(myID, .trained, since: 1_792_515_000_000)
    trained.today.trained = 2
    await backend.set(server: sampleHome(today: trained))
    #expect(today.myStatus == .notCheckedIn)

    await #expect(throws: CheckInError.alreadyTrained) {
        try await today.post(.disclaimer(try Disclaimer("加班")))
    }
    #expect(await backend.saves.isEmpty)
}

@MainActor @Test func aNewPostSendsTheOnesWaitingAheadOfItFirst() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)
    try await today.post(.disclaimer(try Disclaimer("加班到十点")))

    await backend.set(failure: nil)
    #expect(try await today.post(run) != .queued)
    #expect(await backend.saves.map(\.id) == [CheckInID(id(100)), CheckInID(id(101))])
    #expect(today.pending.isEmpty)
    #expect(today.refused.isEmpty)
}

@MainActor @Test func aNewPostWaitsBehindOneThatStillCantGoOut() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(uploadsBeforeFailing: 0)
    try await today.post(.healthyMeal(PostBody(photos: [photo(1)], caption: "")))

    #expect(try await today.post(run) == .queued)
    #expect(await backend.saves.isEmpty)
    #expect(today.pending.map(\.id) == [CheckInID(id(100)), CheckInID(id(101))])
    #expect(today.myStatus == .trained)
}

@MainActor @Test func aPostMadeWhileTheOutboxIsGoingOutFollowsIt() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)
    try await today.post(.disclaimer(try Disclaimer("加班到十点")))

    await backend.set(failure: nil)
    await backend.holdSaves()
    let sending = Task { await today.sendPending() }
    while await backend.savesWaiting == 0 { await Task.yield() }
    // Never sent ahead of the 请假条 already on its way.
    #expect(try await today.post(run) == .queued)
    #expect(await backend.saves.isEmpty)

    await backend.releaseSaves()
    await sending.value
    #expect(await backend.saves.map(\.id) == [CheckInID(id(100)), CheckInID(id(101))])
    #expect(today.pending.isEmpty)
    #expect(today.refused.isEmpty)
}

@MainActor @Test func aRestDayInThePlanOffersNoLeave() async throws {
    var today = sampleToday()
    today.members[1] = entry(myID, .notCheckedIn, plannedRest: true)
    let backend = ScriptedBackend()
    await backend.set(server: sampleHome(today: today))
    let resting = store(backend)
    await resting.load()
    #expect(resting.restsToday)

    let training = store(ScriptedBackend())
    await training.load()
    #expect(!training.restsToday)
}
