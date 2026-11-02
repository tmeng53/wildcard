import Contracts
import Foundation
import Testing

@testable import ScheduleDomain

/// The 每周模板 beside the weeks: shown and planned like a week, saved apart from them, and
/// offered after a week's plan changes.
@MainActor
struct ScheduleStoreTemplateTests {
    /// Thursday 2026-10-22, noon in Los Angeles.
    private let thursday = Fixtures.noon("2026-10-22")
    private let thisWeek = Fixtures.day("2026-10-19")
    private let nextWeek = Fixtures.day("2026-10-26")

    private func store(_ backend: FakeBackend) -> ScheduleStore {
        let now = thursday
        return ScheduleStore(backend: backend, now: { now })
    }

    @Test func theTemplateShowsAsABoardOfItsOwnWithEveryDayOpen() async {
        let store = store(FakeBackend())
        await store.load()
        await store.showTemplate()
        #expect(store.showsTemplate)
        #expect(store.sheet == nil)
        #expect(store.board?.tense == .template)
        #expect(store.board?.weekStart == nextWeek)
        #expect(store.board?.days == Fixtures.plan)
        #expect((0..<7).allSatisfy { store.board?.isEditable($0) == true })
        #expect(store.canEditFuel == false)
        await store.show(thisWeek)
        #expect(store.showsTemplate == false)
        #expect(store.board?.tense == .current)
    }

    @Test func askedForBeforeLoadingItShowsOnceLoaded() async {
        let store = store(FakeBackend())
        await store.showTemplate()
        #expect(store.board == nil)
        await store.load()
        #expect(store.showsTemplate)
        #expect(store.board?.tense == .template)
        #expect(store.shownWeek == nil)
    }

    @Test func aPickOnTheTemplateSavesTheTemplateNotAWeek() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.showTemplate()
        await store.tap(2)
        await store.pick(.sport("swim"))
        var expected = Fixtures.plan
        expected[2] = .train(.sport("swim"))
        #expect(await backend.savedTemplates == [expected])
        #expect(await backend.savedPlans.isEmpty)
        #expect(store.template == expected)
        #expect(store.templateOffer == nil)
    }

    @Test func aRefusedTemplateGoesBackToTheServers() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.showTemplate()
        await backend.failTemplate(with: .notSent)
        await store.tap(0)
        await store.rest()
        #expect(store.failure == .notSent)
        #expect(store.board?.days == Fixtures.plan)
        #expect(store.template == Fixtures.plan)
    }

    @Test func aWeeksChangeOffersToChangeTheTemplateToo() async {
        let backend = FakeBackend()
        let store = store(backend)
        await store.load()
        await store.show(nextWeek)
        await store.tap(2)
        await store.pick(.sport("swim"))
        #expect(store.templateOffer == nextWeek)
        await store.copyToTemplate()
        var expected = Fixtures.plan
        expected[2] = .train(.sport("swim"))
        #expect(await backend.savedTemplates == [expected])
        #expect(store.template == expected)
        #expect(store.templateOffer == nil)
    }

    @Test func aWeekChangedBackToTheTemplateOffersNothing() async {
        let store = store(FakeBackend())
        await store.load()
        await store.show(nextWeek)
        await store.tap(2)
        await store.pick(.sport("swim"))
        #expect(store.templateOffer == nextWeek)
        await store.rest()
        #expect(store.templateOffer == nil)
    }

    @Test func goingToAnotherPageTakesTheOfferAway() async {
        let store = store(FakeBackend())
        await store.load()
        await store.show(nextWeek)
        await store.tap(2)
        await store.pick(.sport("swim"))
        await store.show(thisWeek)
        #expect(store.templateOffer == nil)
    }

    @Test func aRefusedSaveOfNextWeekLeavesTheTemplateShownAlone() async throws {
        let backend = FakeBackend()
        // Next week was saved for itself: all rest, unlike the template.
        let allRest = [PlanDay](repeating: .rest, count: 7)
        await backend.set(try WeekSheet(weekStart: nextWeek, plan: allRest, marks: Array(repeating: .none, count: 7)))
        let store = store(backend)
        await store.load()
        await store.show(nextWeek)
        await backend.holdSaves()
        await backend.failSaves(with: .refused)
        await store.tap(2)
        let saving = Task { await store.pick(.sport("swim")) }
        while await backend.savedPlans.isEmpty { await Task.yield() }
        await store.showTemplate()
        await backend.finishSave()
        await saving.value
        #expect(store.failure == .refused)
        #expect(store.board?.tense == .template)
        #expect(store.board?.days == Fixtures.plan)
    }

    @Test func noOfferBeforeTheTemplateIsKnown() async {
        let backend = FakeBackend()
        await backend.failTemplate(with: .notSent)
        let store = store(backend)
        await store.load()
        await store.show(nextWeek)
        await store.tap(2)
        await store.pick(.sport("swim"))
        #expect(store.templateOffer == nil)
    }
}
