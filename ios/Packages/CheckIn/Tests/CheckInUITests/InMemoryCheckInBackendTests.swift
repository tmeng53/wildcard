import CheckInDomain
import Contracts
import Foundation
import Testing

@testable import CheckInUI

@MainActor private func sampleStore() -> TodayStore {
    TodayStore(
        backend: InMemoryCheckInBackend.sampleSquad(now: Date()), outbox: InMemoryOutbox(), now: { Date() },
        newID: { UUID() })
}

// The squad the UI tests and screenshots run on: 14/22, 3 trained, as the UI tests expect.
@MainActor @Test func theSampleSquadTicksOnceForTheFirstTraining() async throws {
    let store = sampleStore()
    await store.load()
    #expect(store.home?.today.squadWeek == WeekCount(trainedDays: 14, plannedDays: 22))
    #expect(store.home?.today.today.trained == 3)

    try await store.post(.trained(.sport("yoga"), nil, PostBody(photos: [], caption: "")))
    try await store.post(.trained(.sport("run"), nil, PostBody(photos: [], caption: "")))
    await store.load()
    #expect(store.home?.today.squadWeek == WeekCount(trainedDays: 15, plannedDays: 22))
    #expect(store.home?.today.today.trained == 4)
    #expect(store.myStatus == .trained)
}

// The card's my-week page agrees with the count: each day I trained this week shows.
@MainActor @Test func theSampleWeekShowsTheDaysItCounts() async throws {
    let store = sampleStore()
    await store.load()
    let home = try #require(store.home)
    let day = try #require(store.day)
    let week = home.week(on: day)
    #expect(week.days.count { $0 == .trained } == home.today.myWeek.week.trainedDays)
}

@MainActor @Test func theSampleSquadTakesOneDisclaimerBeforeTraining() async throws {
    let store = sampleStore()
    await store.load()
    try await store.post(
        .cheatMeal(PostBody(photos: [PreparedPhoto(id: UUID(), jpeg: Data([1]), size: nil)], caption: "火锅")))
    #expect(store.home?.today.squadWeek.trainedDays == 14)
    try await store.post(.disclaimer(try Disclaimer("加班到十点")))
    #expect(store.myStatus == .disclaimer)
    await #expect(throws: CheckInError.disclaimerAlreadyPosted) {
        try await store.post(.disclaimer(try Disclaimer("又加班")))
    }
}
