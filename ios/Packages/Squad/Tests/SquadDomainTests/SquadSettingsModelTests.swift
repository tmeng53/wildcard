import Contracts
import Foundation
import ScenePickDomain
import SquadDomain
import Testing

private func member(_ last: Int) -> MemberID {
    MemberID(UUID(uuidString: String(format: "a0000000-0000-4000-8000-%012d", last)) ?? UUID())
}

private let (lin, coco, mia) = (member(1), member(2), member(3))
private let squadID = SquadID(UUID(uuidString: "5a000000-0000-4000-8000-000000000001") ?? UUID())

private func character(_ name: String) throws -> MemberCharacter {
    MemberCharacter(nickname: try Nickname(name), look: CharacterLook(persona: "energetic", variants: [:]))
}

private func scene(
    pickers: SquadScene.Pickers, picked: SquadScene.Pick? = nil, canPick: Bool, current: SceneID = .track
) throws -> SquadScene {
    SquadScene(
        week: try LocalDay("2026-10-26"), scene: current, pickers: pickers, picked: picked, canPick: canPick,
        history: [
            SceneHistory(scene: .track, weeksAgo: 0), SceneHistory(scene: .pool, weeksAgo: 2),
            SceneHistory(scene: .gym, weeksAgo: nil),
        ])
}

/// A squad kept in memory: 小林 captains Coco and Mia.
private actor Squad3: SquadSettingsService {
    var current: SquadSettings
    var failing: SquadError?
    private(set) var picks: [SceneID] = []

    init(viewer: MemberID, scene: SquadScene) throws {
        current = SquadSettings(
            squad: Squad(id: squadID, name: "晨跑五人组", inviteCode: "K7Q2M9PX", members: [lin, coco, mia], captain: lin),
            viewer: viewer,
            characters: [lin: try character("小林"), coco: try character("Coco"), mia: try character("Mia")],
            scene: scene)
    }

    func fail(with error: SquadError?) { failing = error }

    func settings() async throws(SquadError) -> SquadSettings {
        if let failing { throw failing }
        return current
    }

    func rename(_ squad: SquadID, to name: SquadName) async throws(SquadError) -> Squad {
        if let failing { throw failing }
        let now = current.squad
        current.squad = Squad(
            id: now.id, name: name.text, inviteCode: now.inviteCode, members: now.members, captain: now.captain)
        return current.squad
    }

    func handCaptaincy(of squad: SquadID, to member: MemberID) async throws(SquadError) -> Squad {
        if let failing { throw failing }
        let now = current.squad
        current.squad = Squad(
            id: now.id, name: now.name, inviteCode: now.inviteCode, members: now.members, captain: member)
        return current.squad
    }

    func remove(_ member: MemberID, from squad: SquadID) async throws(SquadError) {
        if let failing { throw failing }
        let now = current.squad
        current.squad = Squad(
            id: now.id, name: now.name, inviteCode: now.inviteCode, members: now.members.filter { $0 != member },
            captain: now.captain)
    }

    func pick(_ scene: SceneID, for squad: SquadID, week: LocalDay) async throws(SquadError) -> SquadScene {
        if let failing { throw failing }
        picks.append(scene)
        let now = current.scene
        current.scene = SquadScene(
            week: now.week, scene: scene, pickers: now.pickers, picked: .init(scene: scene, picker: current.viewer),
            canPick: false, history: now.history)
        return current.scene
    }
}

@MainActor struct SquadSettingsModelTests {
    @Test func theCaptainSeesEveryoneElseAsManageable() async throws {
        let model = SquadSettingsModel(
            service: try Squad3(viewer: lin, scene: try scene(pickers: .crown([coco]), canPick: false)))
        await model.reload()
        #expect(model.isCaptain)
        #expect(model.captainName == "小林")
        #expect(model.openSpots == 5)
        #expect(model.members.map(\.isManageable) == [false, true, true])
        #expect(model.members.map(\.hasCrown) == [false, true, false])
        #expect(model.sceneLine == .winnersPick(["Coco"]))
        #expect(!model.canPickScene)
    }

    @Test func aMemberManagesNobody() async throws {
        let model = SquadSettingsModel(
            service: try Squad3(viewer: mia, scene: try scene(pickers: .captain(lin), canPick: false)))
        await model.reload()
        #expect(!model.isCaptain)
        #expect(model.members.allSatisfy { !$0.isManageable })
        #expect(model.sceneLine == .captainPicks)
    }

    @Test func renamingSavesTrimmedAndRefusesWhatTheRulesDo() async throws {
        var changes = 0
        let model = SquadSettingsModel(
            service: try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: true)),
            changed: { changes += 1 })
        await model.reload()
        #expect(await model.rename(to: "  夜跑团 "))
        #expect(model.settings?.squad.name == "夜跑团")
        #expect(await !model.rename(to: String(repeating: "跑", count: 21)))
        #expect(await model.rename(to: "夜跑团"))
        #expect(changes == 1)
    }

    @Test func handingTheCaptaincyOnEndsManaging() async throws {
        let model = SquadSettingsModel(
            service: try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: true)))
        await model.reload()
        await model.handCaptaincy(to: coco)
        #expect(!model.isCaptain)
        #expect(model.captainName == "Coco")
        #expect(model.members.allSatisfy { !$0.isManageable })
    }

    @Test func removingAndLeaving() async throws {
        let model = SquadSettingsModel(
            service: try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: true)))
        await model.reload()
        await model.remove(mia)
        #expect(model.members.map(\.id) == [lin, coco])
        #expect(!model.hasLeft)
        await model.leave()
        #expect(model.hasLeft)
    }

    @Test func aChangeThatDoesntGoThroughKeepsTheSquadAndSaysSo() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: true))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await service.fail(with: .unavailable)
        await model.remove(mia)
        #expect(model.changeFailed)
        #expect(model.members.count == 3)
    }

    @Test func theWinnerPicksOnceFromTilesThatKnowTheSquadsHistory() async throws {
        let service = try Squad3(viewer: coco, scene: try scene(pickers: .crown([coco]), canPick: true))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        #expect(model.sceneLine == .youWon)
        model.openPicker()
        let picker = try #require(model.picker)
        #expect(
            picker.options == [
                SceneOption(scene: .track, lastTrained: .thisWeek),
                SceneOption(scene: .pool, lastTrained: .weeksAgo(2)),
                SceneOption(scene: .gym, lastTrained: .never),
            ])
        picker.select(.gym)
        let reveal = await picker.confirm()
        #expect(reveal?.boxed == true)
        await model.picked()
        #expect(await service.picks == [.gym])
        #expect(model.scene == .gym)
        #expect(model.sceneLine == .youPicked)
        #expect(model.picker == nil)
        #expect(!model.canPickScene)
    }

    @Test func aRefusedPickClosesThePickerAndReadsTheSceneAgain() async throws {
        let service = try Squad3(viewer: coco, scene: try scene(pickers: .crown([coco]), canPick: true))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        model.openPicker()
        let picker = try #require(model.picker)
        picker.select(.gym)
        await service.fail(with: .outdated)
        #expect(await picker.confirm() == nil)
        #expect(picker.phase == .failed(.notAllowed))
        await service.fail(with: nil)
        await model.pickRefused()
        #expect(model.picker == nil)
        #expect(await service.picks.isEmpty)
    }
}
