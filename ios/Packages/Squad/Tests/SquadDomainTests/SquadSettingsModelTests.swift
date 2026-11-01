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

private let maotou = Coach(
    id: "xiaohun", name: "毛头", title: "混混教练", catchphrase: "先动起来，证书以后再说",
    background: "体育学院刚毕业，该学的都学了，就是证还没考下来", yearsCoaching: 0, experience: "热情满格",
    style: "懂行、松弛、风趣", tags: ["体院应届", "懂行", "松弛", "风趣"], pay: "管饭就行")
private let nuannuan = Coach(
    id: "nuannuan", name: "暖暖", title: "陪练教练", catchphrase: "慢慢来", background: "陪练三年", yearsCoaching: 3,
    experience: "从不催人", style: "温柔", tags: ["耐心"], pay: "一杯奶茶")
/// Tuesday 2026-10-27, 9am in Toronto.
private let tuesday = Date(timeIntervalSince1970: 1_793_106_000)
private let toronto = TimeZone(identifier: "America/Toronto") ?? .gmt

/// A squad kept in memory: 小林 captains Coco and Mia.
private actor Squad3: SquadSettingsService {
    var current: SquadSettings
    var failing: SquadError?
    private(set) var picks: [SceneID] = []
    private(set) var hires: [CoachID] = []

    init(viewer: MemberID, scene: SquadScene, coach: SquadCoach.Hire? = nil, today: String = "2026-10-27") throws {
        current = SquadSettings(
            squad: Squad(id: squadID, name: "晨跑五人组", inviteCode: "K7Q2M9PX", members: [lin, coco, mia], captain: lin),
            viewer: viewer,
            characters: [lin: try character("小林"), coco: try character("Coco"), mia: try character("Mia")],
            scene: scene, coach: SquadCoach(hire: coach, canHire: viewer == lin), today: try LocalDay(today),
            timeZone: toronto)
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

    func coaches() async throws(SquadError) -> [Coach] {
        if let failing { throw failing }
        return [maotou, nuannuan]
    }

    func hire(_ coach: CoachID, for squad: SquadID) async throws(SquadError) -> SquadCoach {
        if let failing { throw failing }
        guard current.coach.canHire, let hired = [maotou, nuannuan].first(where: { $0.id == coach }) else {
            throw .outdated
        }
        hires.append(coach)
        current.coach = SquadCoach(hire: .init(coach: hired, since: tuesday), canHire: true)
        return current.coach
    }

    func fireCoach(of squad: SquadID) async throws(SquadError) -> SquadCoach {
        if let failing { throw failing }
        guard current.coach.canHire else { throw .outdated }
        current.coach = SquadCoach(hire: nil, canHire: true)
        return current.coach
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
        var changes = 0
        let model = SquadSettingsModel(service: service, changed: { changes += 1 })
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
        #expect(changes == 1)
        #expect(await service.picks.isEmpty)
    }

    @Test func theCaptainHiresChangesAndFiresTheCoach() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .crown([coco]), canPick: false))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        #expect(model.canHireCoach)
        #expect(model.coach == nil)
        #expect(model.coachWeek == nil)

        await model.loadMarket()
        #expect(model.market == .loaded([maotou, nuannuan]))

        #expect(await model.hire("xiaohun") == .done)
        #expect(model.coach?.coach == maotou)
        #expect(model.coachWeek == 1)

        // 换教练 is one step.
        #expect(await model.hire("nuannuan") == .done)
        #expect(model.coach?.coach == nuannuan)
        #expect(await service.hires == ["xiaohun", "nuannuan"])

        #expect(await model.fireCoach() == .done)
        #expect(model.coach == nil)
    }

    @Test func aMateReadsTheCoachButNeverHires() async throws {
        let model = SquadSettingsModel(
            service: try Squad3(
                viewer: mia, scene: try scene(pickers: .crown([coco]), canPick: false),
                coach: .init(coach: maotou, since: tuesday)))
        await model.reload()
        #expect(!model.canHireCoach)
        #expect(model.coach?.coach == maotou)
        #expect(await model.hire("nuannuan") == .outdated)
        #expect(!model.changeFailed)
        #expect(model.coach?.coach == maotou)
    }

    /// A coach change that doesn't get through is the coach page's to say, never 小队设置's.
    @Test func aCoachChangeThatFailsLeavesTheSquadPageAlone() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .crown([coco]), canPick: false))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await service.fail(with: .unavailable)
        #expect(await model.hire("xiaohun") == .unavailable)
        #expect(!model.changeFailed)
        #expect(model.coach == nil)
        await service.fail(with: nil)
        #expect(await model.hire("xiaohun") == .done)
        #expect(model.coach?.coach == maotou)
    }

    /// A coach the market no longer offers is refused; the page reads the squad again.
    @Test func aRetiredCoachIsRefusedAndTheSquadIsReadAgain() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .crown([coco]), canPick: false))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        #expect(await model.hire("retired") == .outdated)
        #expect(!model.changeFailed)
        #expect(model.coach == nil)
        #expect(await service.hires.isEmpty)
    }

    /// The week it was hired counts 1; weeks start on Monday, on the member's clock.
    @Test(arguments: [("2026-10-27", 1), ("2026-11-01", 1), ("2026-11-02", 2), ("2026-11-16", 4)])
    func theCoachsWeekCountsFromTheHire(today: String, week: Int) async throws {
        let model = SquadSettingsModel(
            service: try Squad3(
                viewer: lin, scene: try scene(pickers: .crown([coco]), canPick: false),
                coach: .init(coach: maotou, since: tuesday), today: today))
        await model.reload()
        #expect(model.coachWeek == week)
    }

    @Test func aMarketThatCantBeReadSaysSo() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .crown([coco]), canPick: false))
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await service.fail(with: .unavailable)
        await model.loadMarket()
        #expect(model.market == .failed(.unavailable))
    }
}
