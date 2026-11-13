import AvatarDomain
import Contracts
import Foundation
import OnboardingDomain
import Testing

@testable import OnboardingUI

struct InMemorySignUpServiceTests {
    @Test func everyCodeFindsTheSampleSquad() async throws {
        let service = InMemorySignUpService.sampleSquad()
        let code = try InviteCode("K7Q2M9XD")
        try await service.agreeToAI()
        let preview = try await service.preview(code)
        #expect(preview.code == code)
        #expect(preview.memberCount == 4)
        #expect(preview.isFull == false)
        #expect(preview.needsApproval == false)
        let joined = try Self.joined(await service.join(code, note: nil))
        #expect(joined.teammates.map(\.nickname) == ["可可", "阿杰", "米娅", "豆豆"])
        #expect(joined.weekGoal == 12)
        #expect(joined.daysPerMember == 3)
        #expect(joined.weekDone == 9)
    }

    /// 加入小队 doesn't ask a member back in no squad for AI consent again, so the sample must let
    /// them join without it, as the API does for an account that agreed before.
    @Test func aMemberBackInNoSquadJoinsWithoutAgreeingAgain() async throws {
        let service = InMemorySignUpService.sampleSquad(character: InMemorySignUpService.sampleCharacter)
        let joined = try Self.joined(await service.join(InviteCode("K7Q2M9XD"), note: nil))
        #expect(joined.weekGoal == 12)
    }

    /// 入队申请: a squad whose captain lets members in takes a request, which waits until they say.
    @Test func aCaptainWhoLetsMembersInIsAskedFirst() async throws {
        let service = InMemorySignUpService.sampleSquad(asksCaptain: true)
        let code = try InviteCode("K7Q2M9XD")
        try await service.agreeToAI()
        #expect(try await service.preview(code).needsApproval)
        guard case .asked(let request) = try await service.join(code, note: JoinNote("阿杰拉我来的")) else {
            Issue.record("joined without asking")
            return
        }
        #expect(request.status == .waiting)
        #expect(request.note == "阿杰拉我来的")
        #expect(request.memberCount == 4)
        #expect(request.captain?.nickname.text == "可可")
        #expect(await service.squad == nil)

        await service.answer(approving: true)
        #expect(try await service.joinRequest()?.status == .approved)
        #expect(await service.squad?.name == request.squadName)
    }

    @Test func aWithdrawnRequestIsOver() async throws {
        let service = InMemorySignUpService.sampleSquad(asksCaptain: true)
        try await service.agreeToAI()
        _ = try await service.join(InviteCode("K7Q2M9XD"), note: nil)
        try await service.withdrawJoinRequest()
        #expect(try await service.joinRequest()?.status == .over)
        await service.answer(approving: true)
        #expect(await service.squad == nil)
    }

    private static func joined(_ outcome: JoinOutcome) throws -> JoinedSquad {
        guard case .joined(let squad) = outcome else { throw SignUpError.rejected }
        return squad
    }

    @Test func aNewSquadHasOnlyTheMember() async throws {
        let service = InMemorySignUpService.sampleSquad()
        try await service.agreeToAI()
        let squad = try await service.create(named: SquadName("周末爬山队"), daysPerMember: 5, timeZone: "America/New_York")
        #expect(squad.name == "周末爬山队")
        #expect(squad.teammates.isEmpty)
        #expect(squad.weekGoal == 0)
        #expect(squad.daysPerMember == 5)
        await #expect(throws: SignUpError.rejected) {
            try await service.create(named: SquadName("周末爬山队"), daysPerMember: 8, timeZone: "America/New_York")
        }
    }

    @Test func theSquadMadePicksItsSceneOnce() async throws {
        let service = InMemorySignUpService.sampleSquad()
        try await service.agreeToAI()
        let squad = try await service.create(named: SquadName("周末爬山队"), daysPerMember: 3, timeZone: "America/New_York")
        try await service.pickScene(.pool, for: squad.id)
        try await service.pickScene(.pool, for: squad.id)
        await #expect(throws: SignUpError.rejected) { try await service.pickScene(.gym, for: squad.id) }
        #expect(await service.scene == .pool)
    }

    @Test func noSquadWithoutAgreeingToAI() async throws {
        let service = InMemorySignUpService.sampleSquad()
        await #expect(throws: SignUpError.rejected) {
            try await service.create(named: SquadName("周末爬山队"), daysPerMember: 3, timeZone: "America/New_York")
        }
        await #expect(throws: SignUpError.rejected) { try await service.join(InviteCode("K7Q2M9XD"), note: nil) }
    }

    @Test func aPlanMustBeAWholeWeek() async throws {
        let service = InMemorySignUpService.sampleSquad()
        await #expect(throws: SignUpError.rejected) { try await service.savePlan([.rest]) }
        try await service.savePlan(Array(repeating: .rest, count: 7))
        #expect(await service.plan?.count == 7)
    }

    @Test func aClosedSignUpCarriesOnWithItsSquadAndCharacter() async throws {
        let service = InMemorySignUpService.sampleSquad()
        let character = NewCharacter(
            outfit: Outfit(["body": "shiba"]), persona: .energetic, nickname: try Nickname("Tracy"))
        try await service.save(character)
        try await service.agreeToAI()
        let joined = try Self.joined(await service.join(InviteCode("K7Q2M9XD"), note: nil))
        let resumed = try await service.resume(in: joined.id)
        #expect(resumed.squad == joined)
        #expect(resumed.character == character)
        await #expect(throws: SignUpError.rejected) { try await service.resume(in: SquadID(UUID())) }
    }
}
