import Contracts
import Foundation
import Testing

@testable import ScheduleDomain

/// Saving while saves, loads and refusals overlap, against a server in memory.
@MainActor
struct ScheduleStoreSavingTests {
    /// Thursday 2026-10-22, noon in Los Angeles.
    private let thursday = Fixtures.noon("2026-10-22")
    private let thisWeek = Fixtures.day("2026-10-19")

    private func store(_ backend: FakeBackend) -> ScheduleStore {
        let now = thursday
        return ScheduleStore(backend: backend, now: { now })
    }

    @Test func aFailedSavePutsTheWeekBackAndSaysWhy() async {
        let backend = FakeBackend()
        await backend.failSaves(with: .restDaysFixed)
        let store = store(backend)
        await store.load()
        await store.tap(4)
        await store.pick(.sport(.yoga))
        #expect(store.failure == .restDaysFixed)
        #expect(store.sheet?.plan == Fixtures.plan)
        #expect(store.board?.focus == WeekBoard.Focus.none)
    }

    @Test func aChangeMadeWhileSavingGoesOutAfterwardWithTheLatestDays() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: 7))
        await backend.holdSaves()
        await store.tap(0)
        let first = Task { await store.pick(.sport(.swim)) }
        while await backend.savedPlans.isEmpty { await Task.yield() }
        await store.pick(.sport(.yoga))
        await store.pick(.sport(.hike))
        await backend.finishSave()
        await first.value
        let saved = await backend.savedPlans
        #expect(saved.map { $0.first } == [.train(.sport(.swim)), .train(.sport(.hike))])
        #expect(store.sheet?.plan.first == .train(.sport(.hike)))
    }

    @Test func aFailedSaveAfterOneThatWentThroughKeepsWhatTheServerHolds() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: 7))
        await backend.failSaves(with: .notSent, after: 1)
        await backend.holdSaves()
        await store.tap(0)
        let first = Task { await store.pick(.sport(.swim)) }
        while await backend.savedPlans.isEmpty { await Task.yield() }
        await store.tap(1)
        await store.pick(.sport(.yoga))
        await backend.finishSave()
        await first.value
        #expect(store.failure == .notSent)
        #expect(store.sheet?.plan[0] == .train(.sport(.swim)))
        #expect(store.sheet?.plan[1] == .train(.sport(.tennis)))
        #expect(store.board?.days[0] == .train(.sport(.swim)))
        #expect(store.board?.days[1] == .train(.sport(.tennis)))
    }

    @Test func aFailedPlanSaveKeepsAFoodGoalTheServerTook() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: 7))
        await backend.failSaves(with: .notSent, after: 0)
        await backend.holdSaves()
        await store.tap(0)
        let plan = Task { await store.pick(.sport(.swim)) }
        while await backend.savedPlans.isEmpty { await Task.yield() }
        await store.toggleFuel(.suggested(.water))
        await backend.finishSave()
        await plan.value
        #expect(store.failure == .notSent)
        #expect(store.sheet?.plan[0] == .train(.sport(.run)))
        #expect(store.sheet?.fuel == [.suggested(.water)])
    }

    @Test func aFoodGoalTappedWhileOneSavesGoesOutAfterIt() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: 7))
        await backend.holdSaves()
        let first = Task { await store.toggleFuel(.suggested(.water)) }
        while await backend.savedFuel.isEmpty { await Task.yield() }
        await store.toggleFuel(.suggested(.veggies))
        #expect(await backend.savedFuel.count == 1)
        await backend.finishSave()
        await first.value
        #expect(await backend.savedFuel == [[.suggested(.water)], [.suggested(.water), .suggested(.veggies)]])
        #expect(store.sheet?.fuel == [.suggested(.water), .suggested(.veggies)])
        #expect(store.failure == nil)
    }

    @Test func aChangeWaitingOnASaveGoesOutAfterTheMemberOpensAnotherWeek() async {
        let backend = FakeBackend()
        let store = store(backend)
        let nextWeek = thisWeek.adding(days: 7)
        await store.load()
        await store.show(nextWeek)
        await backend.holdSaves()
        await store.tap(0)
        let first = Task { await store.pick(.sport(.swim)) }
        while await backend.savedPlans.isEmpty { await Task.yield() }
        await store.tap(1)
        await store.pick(.sport(.yoga))
        await store.show(thisWeek)
        await backend.finishSave()
        await first.value
        #expect(await backend.savedPlans.count == 2)
        #expect(await backend.savedPlans.last?[1] == .train(.sport(.yoga)))
        await store.show(nextWeek)
        #expect(store.board?.days[0] == .train(.sport(.swim)))
        #expect(store.board?.days[1] == .train(.sport(.yoga)))
    }

    @Test func aLoadAskedForBeforeAChangeDoesNotUndoIt() async {
        let backend = FakeBackend()
        let store = store(backend)
        let nextWeek = thisWeek.adding(days: 7)
        await store.load()
        await store.show(nextWeek)
        await backend.holdLoads()
        let reload = Task { await store.show(nextWeek) }
        while await backend.loadsWaiting == 0 { await Task.yield() }
        await store.tap(0)
        await store.pick(.sport(.swim))
        await backend.finishLoad()
        await reload.value
        #expect(store.board?.days[0] == .train(.sport(.swim)))
        #expect(store.sheet?.plan[0] == .train(.sport(.swim)))
    }

    @Test func thePosterShowsThePlanTheServerKept() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(thisWeek.adding(days: 7))
        await backend.keepPlans { days in days.map { $0 == .train(.sport(.swim)) ? .train(.sport(.run)) : $0 } }
        await store.tap(0)
        await store.pick(.sport(.swim))
        #expect(store.board?.days[0] == .train(.sport(.run)))
        #expect(store.sheet?.plan[0] == .train(.sport(.run)))
    }
}
