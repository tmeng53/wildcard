import Contracts
import Foundation
import ScenePickDomain
import SquadDomain
import Testing

/// 小队设置's 比赛时区: the captain changes it, at once; everyone else reads it.
@MainActor struct SquadTimeZoneTests {
    @Test func theCaptainSetsTheTimeZoneAtOnceAndAMateOnlyReadsIt() async throws {
        let captain = SquadSettingsModel(
            service: try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false)))
        await captain.reload()
        #expect(captain.canChangeTimeZone)
        await captain.setTimeZone("America/New_York")
        #expect(captain.matchTimeZone?.timeZone == "America/New_York")
        await captain.setTimeZone("Mars/Olympus")
        #expect(captain.matchTimeZone?.timeZone == "America/New_York")

        let mate = SquadSettingsModel(
            service: try Squad3(viewer: mia, scene: try scene(pickers: .captain(lin), canPick: false)))
        await mate.reload()
        #expect(!mate.canChangeTimeZone)
        await mate.setTimeZone("America/New_York")
        #expect(mate.matchTimeZone?.timeZone == "Asia/Taipei")
    }

    @Test func aTimeZoneThatDoesNotGoThroughMovesBack() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await service.fail(with: .unavailable)
        await model.setTimeZone("Europe/London")
        #expect(model.changeFailed)
        #expect(model.matchTimeZone?.timeZone == "Asia/Taipei")
    }
}
