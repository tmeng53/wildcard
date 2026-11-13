import Contracts
import Foundation
import SquadDomain
import Testing

private let juju = MemberID(UUID(uuidString: "a0000000-0000-4000-8000-000000000009") ?? UUID())
private let jujuAsks = WaitingJoinRequest(
    id: JoinRequestID(UUID(uuidString: "b0000000-0000-4000-8000-000000000001") ?? UUID()), member: juju,
    character: nil, note: "我是小橘，阿杰拉我来的", askedAt: Date(timeIntervalSince1970: 1_793_100_000))

extension Squad3 {
    func ask(_ request: WaitingJoinRequest, required: Bool = true) {
        current.joining = SquadJoining(required: required, requests: [request])
    }

    func fill() {
        let now = current.squad
        let others = (10...14).map {
            MemberID(UUID(uuidString: String(format: "a0000000-0000-4000-8000-%012d", $0)) ?? UUID())
        }
        current.squad = Squad(
            id: now.id, name: now.name, inviteCode: now.inviteCode, members: now.members + others, captain: now.captain)
    }

    func answer(_ request: JoinRequestID, in squad: SquadID, approve: Bool) async throws(SquadError) {
        if let failing { throw failing }
        guard let asked = current.joining?.requests.first(where: { $0.id == request }) else { throw .outdated }
        current.joining?.requests.removeAll { $0.id == request }
        if approve {
            let now = current.squad
            current.squad = Squad(
                id: now.id, name: now.name, inviteCode: now.inviteCode, members: now.members + [asked.member],
                captain: now.captain)
        }
    }

    func setJoinApproval(of squad: SquadID, required: Bool) async throws(SquadError) -> Bool {
        if let failing { throw failing }
        guard current.joining != nil else { throw .outdated }
        current.joining?.required = required
        return required
    }
}

/// 入队申请 and 入队需要审核 on 小队设置: the captain's, answered and switched from there.
@MainActor struct SquadJoiningTests {
    @Test func aYesLetsTheMemberInAndTheirRequestGoes() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        await service.ask(jujuAsks)
        let model = SquadSettingsModel(service: service)
        await model.reload()
        #expect(model.waitingRequests == 1)
        await model.answer(jujuAsks, approve: true)
        #expect(model.waitingRequests == 0)
        #expect(model.settings?.squad.members == [lin, coco, mia, juju])
    }

    @Test func aNoTakesTheRowAwayAndLetsNobodyIn() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        await service.ask(jujuAsks)
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await model.answer(jujuAsks, approve: false)
        #expect(model.waitingRequests == 0)
        #expect(model.settings?.squad.members == [lin, coco, mia])
    }

    @Test func aFullSquadCanOnlyTurnAway() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        await service.ask(jujuAsks)
        await service.fill()
        let model = SquadSettingsModel(service: service)
        await model.reload()
        #expect(!model.canApprove)
        await model.answer(jujuAsks, approve: true)
        #expect(model.waitingRequests == 1)
        #expect(model.settings?.squad.members.contains(juju) == false)
    }

    @Test func anAnswerThatDoesNotGoThroughKeepsTheRow() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        await service.ask(jujuAsks)
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await service.fail(with: .unavailable)
        await model.answer(jujuAsks, approve: false)
        #expect(model.changeFailed)
        #expect(model.waitingRequests == 1)
    }

    @Test func theSwitchMovesAtOnceAndBackWhenTheChangeFails() async throws {
        let service = try Squad3(viewer: lin, scene: try scene(pickers: .captain(lin), canPick: false))
        await service.ask(jujuAsks)
        let model = SquadSettingsModel(service: service)
        await model.reload()
        await model.setJoinApproval(false)
        #expect(model.joining?.required == false)
        await service.fail(with: .unavailable)
        await model.setJoinApproval(true)
        #expect(model.changeFailed)
        #expect(model.joining?.required == false)
    }

    @Test func aMateSeesNoRequestsAndNoSwitch() async throws {
        let model = SquadSettingsModel(
            service: try Squad3(viewer: mia, scene: try scene(pickers: .captain(lin), canPick: false)))
        await model.reload()
        #expect(model.joining == nil)
        #expect(model.waitingRequests == 0)
        await model.setJoinApproval(false)
        #expect(model.joining == nil)
    }
}
