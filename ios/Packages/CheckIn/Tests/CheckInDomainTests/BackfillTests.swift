import CheckInDomain
import Contracts
import Testing

private let run = CheckInDraft.trained(.sport("run"), nil, PostBody(photos: [], caption: ""))

@MainActor @Test func aPostCanCountForTodayOrTheWeekBefore() async throws {
    let today = store(ScriptedBackend())
    #expect(today.postableDays == [])
    await today.load()
    #expect(
        today.postableDays.map(\.description) == [
            "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18", "2026-10-19",
            "2026-10-20",
        ])
}

@MainActor @Test func aBackfillKeepsTheDayItWasPostedOn() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    let outcome = try await today.post(run, on: try LocalDay("2026-10-18"))
    guard case .posted(let saved) = outcome else {
        Issue.record("expected posted, got \(outcome)")
        return
    }
    #expect(saved.day.description == "2026-10-18")
    #expect(saved.postedDay.description == "2026-10-20")
    #expect(saved.isBackfill)
    #expect(await backend.saves.map(\.postedDay.description) == ["2026-10-20"])
    // Today is as it was: the past day's 练了 doesn't train today.
    #expect(today.myStatus != .trained)
    #expect(today.trainedDays.map(\.description) == ["2026-10-18"])
}

@MainActor @Test func aDayOutOfReachIsRefused() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    await #expect(throws: CheckInError.refused) {
        try await today.post(run, on: try LocalDay("2026-10-12"))
    }
    await #expect(throws: CheckInError.refused) {
        try await today.post(run, on: try LocalDay("2026-10-21"))
    }
    #expect(await backend.saves.isEmpty)
}

@MainActor @Test func aDisclaimerCanGoOnAPastDayWithoutATraining() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    _ = try await today.post(run)
    _ = try await today.post(run, on: try LocalDay("2026-10-19"))

    // Today and Monday have a 练了; Sunday doesn't.
    await #expect(throws: CheckInError.alreadyTrained) {
        try await today.post(.disclaimer(try Disclaimer("累")), on: try LocalDay("2026-10-19"))
    }
    let outcome = try await today.post(.disclaimer(try Disclaimer("累")), on: try LocalDay("2026-10-18"))
    guard case .posted(let saved) = outcome else {
        Issue.record("expected posted, got \(outcome)")
        return
    }
    #expect(saved.day.description == "2026-10-18")
    #expect(today.trainedDays.map(\.description).sorted() == ["2026-10-19", "2026-10-20"])
}

@Test func aPostMadeOnItsOwnDayIsNoBackfill() throws {
    let day = try LocalDay("2026-10-20")
    let checkIn = CheckIn(
        id: CheckInID(id(1)), member: myID, day: day, createdAt: Timestamp(millisecondsSince1970: 0),
        audience: try Audience([squadID]), entry: .healthyMeal(Meal()))
    #expect(checkIn.postedDay == day)
    #expect(!checkIn.isBackfill)
}
