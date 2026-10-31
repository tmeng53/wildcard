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
        let joined = try await service.join(code)
        #expect(joined.teammates.map(\.nickname) == ["可可", "阿杰", "米娅", "豆豆"])
        #expect(joined.weekGoal == 22)
        #expect(joined.weekDone == 14)
    }

    @Test func aNewSquadHasOnlyTheMember() async throws {
        let service = InMemorySignUpService.sampleSquad()
        try await service.agreeToAI()
        let squad = try await service.create(named: SquadName("周末爬山队"))
        #expect(squad.name == "周末爬山队")
        #expect(squad.teammates.isEmpty)
        #expect(squad.weekGoal == 0)
    }

    @Test func theSquadMadePicksItsSceneOnce() async throws {
        let service = InMemorySignUpService.sampleSquad()
        try await service.agreeToAI()
        let squad = try await service.create(named: SquadName("周末爬山队"))
        try await service.pickScene(.pool, for: squad.id)
        try await service.pickScene(.pool, for: squad.id)
        await #expect(throws: SignUpError.rejected) { try await service.pickScene(.gym, for: squad.id) }
        #expect(await service.scene == .pool)
    }

    @Test func noSquadWithoutAgreeingToAI() async throws {
        let service = InMemorySignUpService.sampleSquad()
        await #expect(throws: SignUpError.rejected) { try await service.create(named: SquadName("周末爬山队")) }
        await #expect(throws: SignUpError.rejected) { try await service.join(InviteCode("K7Q2M9XD")) }
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
        let joined = try await service.join(InviteCode("K7Q2M9XD"))
        let resumed = try await service.resume(in: joined.id)
        #expect(resumed.squad == joined)
        #expect(resumed.character == character)
        await #expect(throws: SignUpError.rejected) { try await service.resume(in: SquadID(UUID())) }
    }
}
