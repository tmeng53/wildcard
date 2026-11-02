import Contracts
import DesignSystem
import Foundation
import ScenePickDomain
import SquadDomain
import Testing

@testable import Backend

// 小队设置's adapters against the built API and local Supabase: the page as the captain and a
// member read it, the captain's changes, leaving, and the scene pick.

@Test func theCaptainRenamesHandsOnAndRemovesAndTheMemberSeesIt() async throws {
    let stack = try LocalStack()
    let (captain, mate, third) = (
        try await stack.signedInMember(), try await stack.signedInMember(), try await stack.signedInMember()
    )
    let squad = try await stack.squad(of: captain, mate, third)
    let captains = APISquadSettingsService(api: captain.api)
    let mates = APISquadSettingsService(api: mate.api)

    let read = try await captains.settings()
    #expect(read.squad.id == squad)
    #expect(read.viewer == captain.id)
    #expect(read.squad.captain == captain.id)
    #expect(read.squad.members == [captain.id, mate.id, third.id])
    // Nobody won a crown before the squad's first week: the captain picks.
    #expect(read.scene.pickers == .captain(captain.id))
    #expect(read.scene.canPick)

    #expect(try await captains.rename(squad, to: try SquadName("夜跑团")).name == "夜跑团")
    await #expect(throws: SquadError.outdated) { _ = try await mates.rename(squad, to: try SquadName("乱改")) }
    try await captains.remove(third.id, from: squad)
    #expect(try await captains.handCaptaincy(of: squad, to: mate.id).captain == mate.id)

    let seen = try await mates.settings()
    #expect(seen.squad.name == "夜跑团")
    #expect(seen.squad.members == [captain.id, mate.id])
    #expect(seen.squad.captain == mate.id)

    try await captains.remove(captain.id, from: squad)
    await #expect(throws: SquadError.noSquad) { _ = try await captains.settings() }
}

@Test func theScenePickIsMadeOnceAndARetryAnswersTheSame() async throws {
    let stack = try LocalStack()
    let (captain, mate) = (try await stack.signedInMember(), try await stack.signedInMember())
    let squad = try await stack.squad(of: captain, mate)
    let week = try await APISquadSettingsService(api: captain.api).settings().scene.week

    await #expect(throws: ScenePickError.notAllowed) {
        try await APIScenePickService(api: mate.api, squad: squad, week: week).pick(.gym)
    }
    let picker = APIScenePickService(api: captain.api, squad: squad, week: week)
    try await picker.pick(.gym)
    try await picker.pick(.gym)
    await #expect(throws: ScenePickError.notAllowed) { try await picker.pick(.pool) }

    let seen = try await APISquadSettingsService(api: mate.api).settings().scene
    #expect(seen.picked == SquadScene.Pick(scene: .gym, picker: captain.id))
    #expect(!seen.canPick)
}

@Test func theCaptainHiresAndFiresTheCoachAndTheMateSeesIt() async throws {
    let stack = try LocalStack()
    let (captain, mate) = (try await stack.signedInMember(), try await stack.signedInMember())
    let squad = try await stack.squad(of: captain, mate)
    let captains = APISquadSettingsService(api: captain.api)
    let mates = APISquadSettingsService(api: mate.api)

    let first = try await captains.settings()
    #expect(first.coach == SquadCoach(hire: nil, canHire: true))
    let market = try await captains.coaches()
    let coach = try #require(market.first { $0.id == "xiaohun" })
    #expect(!coach.tags.isEmpty)

    await #expect(throws: SquadError.outdated) { _ = try await mates.hire(coach.id, for: squad) }
    let hired = try await captains.hire(coach.id, for: squad)
    #expect(hired.hire?.coach == coach)
    #expect(try await captains.hire(coach.id, for: squad) == hired)

    let seen = try await mates.settings().coach
    #expect(seen.hire?.coach.id == coach.id)
    #expect(!seen.canHire)

    #expect(try await captains.fireCoach(of: squad) == SquadCoach(hire: nil, canHire: true))
    #expect(try await mates.settings().coach.hire == nil)
}
