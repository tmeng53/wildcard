import Contracts
import Foundation
import Testing

@testable import ScheduleDomain

/// Loading weeks and saving every change, against a server in memory.
@MainActor
struct ScheduleStoreTests {
    /// Thursday 2026-10-22, noon in Los Angeles.
    private let thursday = Fixtures.noon("2026-10-22")
    private let thisWeek = Fixtures.day("2026-10-19")

    private func store(_ backend: FakeBackend, at moment: Date? = nil) -> ScheduleStore {
        let now = moment ?? thursday
        return ScheduleStore(backend: backend, now: { now })
    }

    @Test func loadShowsThisWeekWithTheLifetimeCount() async throws {
        let backend = FakeBackend()
        await backend.set(
            try WeekSheet(
                weekStart: thisWeek, plan: Fixtures.plan,
                marks: [.trained, .disclaimer, .none, .trained, .none, .none, .none],
                squad: SquadCount(trained: 14, planned: 22)))
        let store = store(backend)
        await store.load()
        #expect(store.phase == .ready)
        #expect(store.shownWeek == thisWeek)
        #expect(store.board?.tense == .current)
        #expect(store.sheet?.trainedDays == 2)
        #expect(store.sheet?.plannedDays == 5)
        #expect(store.sheet?.squad == SquadCount(trained: 14, planned: 22))
        #expect(store.lifetimeTrainedDays == 46)
    }

    @Test func weeksRunFromTheJoinedWeekToNextWeek() async {
        let store = store(FakeBackend(firstWeek: Fixtures.day("2026-10-08")))
        await store.load()
        #expect(store.weeks == ["2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"].map(Fixtures.day))
    }

    @Test func weeksReachBackEightWeeksAtMost() async {
        let store = store(FakeBackend(firstWeek: Fixtures.day("2025-01-06")))
        await store.load()
        #expect(store.weeks.count == ScheduleStore.maxPastWeeks + 2)
        #expect(store.weeks.first == Fixtures.day("2026-08-24"))
        #expect(store.weeks.last == Fixtures.day("2026-10-26"))
    }

    @Test func signedOutAndOfflineSayWhere() async {
        let backend = FakeBackend()
        await backend.failProfile(with: .signedOut)
        let signedOut = store(backend)
        await signedOut.load()
        #expect(signedOut.phase == .signedOut)
        await backend.failProfile(with: .notSent)
        let offline = store(backend)
        await offline.load()
        #expect(offline.phase == .offline)
        #expect(offline.weeks.isEmpty)
    }

    @Test func aDayStillToComeThisWeekRestsAndIsSavedAtOnce() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        #expect(await store.tap(4) == .selected)
        #expect(await backend.savedPlans.isEmpty, "selecting saves nothing")
        await store.rest()
        var rested = Fixtures.plan
        rested[4] = .rest
        #expect(await backend.savedPlans == [rested])
        #expect(store.sheet?.plan == rested)
        #expect(store.failure == nil)
    }

    @Test func pickingASportSavesTheWeek() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: 7))
        await store.tap(0)
        await store.pick(.sport("swim"))
        await store.rest()
        let saved = await backend.savedPlans
        #expect(saved.count == 2)
        #expect(saved.first?.first == .train(.sport("swim")))
        #expect(saved.last?.first == .rest)
    }

    @Test func aPastWeekCantChange() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: -7))
        #expect(await store.tap(0) == .locked)
        await store.pick(.sport("swim"))
        #expect(await backend.savedPlans.isEmpty)
        #expect(!store.canEditFuel)
    }

    @Test func suggestedSportsStartWithTheWeeksOwn() async {
        let store = store(FakeBackend())
        await store.load()
        #expect(
            store.suggestedActivities(common: ["run", "strength", "yoga", "swim", "tennis", "hike"]) == [
                .sport("run"), .sport("tennis"), .sport("strength"), .sport("yoga"), .sport("swim"),
            ]
        )
    }

    @Test func fuelGoalsChangeThisWeekAndLaterAndHoldThree() async throws {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        #expect(store.canEditFuel, "this week's goals change too")
        await store.toggleFuel(.suggested(.water))
        #expect(await backend.savedFuel.count == 1)

        await store.show(thisWeek.adding(days: 7))
        #expect(store.canEditFuel)
        await store.toggleFuel(.suggested(.water))
        await store.toggleFuel(.suggested(.veggies))
        try await store.addFuel(typed: "  少喝咖啡 ")
        await store.toggleFuel(.suggested(.breakfast))
        #expect(store.sheet?.fuel == [.suggested(.water), .suggested(.veggies), .own("少喝咖啡")])
        await store.toggleFuel(.suggested(.water))
        #expect(store.sheet?.fuel == [.suggested(.veggies), .own("少喝咖啡")])
        #expect(await backend.savedFuel.count == 5)
    }

    @Test func anOwnFuelGoalIsOneShortLine() throws {
        #expect(throws: ScheduleError.invalidFuelGoal) { try FuelGoal.own(typed: "   ") }
        #expect(throws: ScheduleError.invalidFuelGoal) { try FuelGoal.own(typed: "一二三四五六七八九") }
        #expect(throws: ScheduleError.invalidFuelGoal) { try FuelGoal.own(typed: "早\n睡") }
        #expect(try FuelGoal.own(typed: "一二三四五六七八") == .own("一二三四五六七八"))
    }

    @Test func aFailedFuelSaveTakesTheGoalOff() async {
        let backend = FakeBackend()
        await backend.failSaves(with: .notSent)
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: 7))
        await store.toggleFuel(.suggested(.water))
        #expect(store.sheet?.fuel == [])
        #expect(store.failure == .notSent)
    }

    @Test func theCountdownRunsToMidnightOnMonday() async {
        // Thursday noon to Monday 00:00 in Los Angeles: 3 days 12 hours.
        let store = store(FakeBackend())
        await store.load()
        #expect(
            store.untilNextWeek == Countdown(from: thursday, until: Fixtures.day("2026-10-26"), in: Fixtures.losAngeles)
        )
        let countdown = store.untilNextWeek
        #expect(countdown?.days == 3)
        #expect(countdown?.hours == 12)
        #expect(countdown?.minutes == 0)
        // 3 days 11:17:47 later, 42 minutes 13 seconds are left.
        let later: TimeInterval = 299_867
        let late = Countdown(
            from: thursday.addingTimeInterval(later), until: Fixtures.day("2026-10-26"), in: Fixtures.losAngeles)
        let lateParts: [Int] = [late.days, late.hours, late.minutes, late.seconds]
        #expect(lateParts == [0, 0, 42, 13])
        let over = Countdown(from: thursday, until: Fixtures.day("2026-10-19"), in: Fixtures.losAngeles)
        let overParts: [Int] = [over.days, over.hours, over.minutes, over.seconds]
        #expect(overParts == [0, 0, 0, 0])
    }
}
