import Contracts
import Foundation
import ScenePickDomain
import SquadDomain
import Testing

/// The squad's settings the captain changes and everyone else reads: its weekly goal and language.
@MainActor struct SquadSettingsChangeTests {
    @Test func theCaptainSetsTheGoalForNextWeekAndAMateOnlyReadsIt() async throws {
        let captain = SquadSettingsModel(
            service: try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false)))
        await captain.reload()
        #expect(captain.canChangeGoal)
        await captain.setGoal(5)
        #expect(captain.goal?.daysPerMember == 3)
        #expect(captain.goal?.nextDaysPerMember == 5)
        await captain.setGoal(8)
        #expect(captain.goal?.nextDaysPerMember == 5)

        let mate = SquadSettingsModel(
            service: try Squad3(viewer: mia, scene: try scene(pickers: .captain(lin), canPick: false)))
        await mate.reload()
        #expect(!mate.canChangeGoal)
        #expect(mate.goal?.recent == SquadWeeklyGoal.Recent(weeks: 2, daysPerMember: 3.4))
        await mate.setGoal(5)
        #expect(mate.goal?.nextDaysPerMember == 3)
    }

    @Test func aGoalThatDoesNotGoThroughMovesBack() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await service.fail(with: .unavailable)
        await model.setGoal(6)
        #expect(model.changeFailed)
        #expect(model.goal?.nextDaysPerMember == 3)
    }

    @Test func theCaptainSetsTheSquadsLanguageAtOnceAndAMateOnlyReadsIt() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        let captain = SquadSettingsModel(service: service)
        await captain.reload()
        #expect(captain.canChangeLanguage)
        await captain.setLanguage(.english)
        #expect(captain.language?.language == .english)
        #expect(!captain.changeFailed)
        // Picking the language shown still saves it, so the squad stops following the captain's app.
        await captain.setLanguage(.english)
        #expect(await service.languagePicks == [.english, .english])

        let mate = SquadSettingsModel(
            service: try Squad3(viewer: mia, scene: try scene(pickers: .captain(lin), canPick: false)))
        await mate.reload()
        #expect(!mate.canChangeLanguage)
        await mate.setLanguage(.english)
        #expect(mate.language?.language == .traditionalChinese)
    }

    @Test func aLanguageThatDoesNotGoThroughMovesBack() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await service.fail(with: .unavailable)
        await model.setLanguage(.simplifiedChinese)
        #expect(model.changeFailed)
        #expect(model.language?.language == .traditionalChinese)
    }
}
