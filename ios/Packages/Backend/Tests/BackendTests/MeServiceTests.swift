import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import MeDomain
import OnboardingDomain
import Testing

@testable import Backend

// 我's adapter against the built API and local Supabase: what the tab shows, its switch, an
// edited character and deleting the account.

@Test func meShowsTheCharacterTheCountsTheSquadAndTheSwitch() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let signUp = APISignUpService(api: member.api)
    try await signUp.save(
        NewCharacter(outfit: Outfit(["body": "shiba"]), persona: .drama, nickname: try Nickname("阿杰")))
    try await signUp.agreeToAI()
    let squad = try await signUp.create(named: try SquadName("早八健身"))
    let service = APIMeService(api: member.api)
    // 本周 is the squad's today's count for the member; how many days the plan holds depends on
    // the weekday the test runs, since a week counts only from the day the member joined.
    let week = try await member.api.today(of: squad.id).myWeek.week
    #expect(week.trainedDays == 0)
    let joinedAt = try #require(try await member.api.me().joinedAt)

    #expect(
        try await service.overview()
            == MeOverview(
                character: MeCharacter(nickname: "阿杰", outfit: Outfit(["body": "shiba"]), persona: .drama),
                joinedAt: joinedAt.date,
                counts: .zero, week: week, squadName: "早八健身", dailyPushOn: true))

    try await service.setDailyPush(false)
    #expect(try await service.overview().dailyPushOn == false)
}

@Test func anEditedCharacterKeepsTheRestOfTheProfile() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let zone = try #require(TimeZone(identifier: "America/Toronto"))
    _ = try await member.api.save(Profile(timeZone: zone, catchphrase: try Catchphrase("冲就完了")))
    let service = APIMeService(api: member.api)

    try await service.save(MeCharacter(nickname: "豆豆", outfit: Outfit(["body": "bear"]), persona: .shy))

    let profile = try #require(try await member.api.me().profile)
    #expect(profile.timeZone == zone)
    #expect(profile.catchphrase == (try Catchphrase("冲就完了")))
    #expect(
        try await service.overview().character
            == MeCharacter(nickname: "豆豆", outfit: Outfit(["body": "bear"]), persona: .shy))
    await #expect(throws: MeError.rejected) {
        try await service.save(MeCharacter(nickname: "", outfit: Outfit(["body": "bear"]), persona: .shy))
    }
}

@Test func deletingTheAccountUnregistersFirstAndLeavesNothing() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    _ = try await stack.squad(of: member)
    let unregistered = Flag()
    let service = APIMeService(api: member.api, beforeDeleting: { await unregistered.set() })

    try await service.deleteAccount(.signedInSession)

    #expect(await unregistered.isSet)
    // The account is gone: its session is refused from here on.
    try await member.account.signOut()
    await #expect(throws: MeError.signedOut) { try await service.overview() }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}
