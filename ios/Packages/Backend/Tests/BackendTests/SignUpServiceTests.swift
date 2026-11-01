import AvatarArt
import AvatarDomain
import CheckInDomain
import Contracts
import Foundation
import OnboardingDomain
import Testing

@testable import Backend

// Sign-up's adapter against the built API and local Supabase: the squad, the character and the
// first week's plan land where the home reads them.

private func character(_ nickname: String, body: String, persona: Persona) throws -> NewCharacter {
    NewCharacter(
        outfit: Outfit(
            ["body": body, "top": "warmup-tee"], colors: ["top": RGBAColor(red: 58, green: 123, blue: 213)]),
        persona: persona, nickname: try Nickname(nickname))
}

@Test func aNewMemberMakesASquadTheirCharacterAndTheirWeek() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let signUp = APISignUpService(api: member.api)

    #expect(try await member.api.hasAgreedToAI() == false)
    try await signUp.save(try character("小林", body: "calico", persona: .shy))
    try await signUp.agreeToAI()
    let squad = try await signUp.create(named: try SquadName("周三不练腿"))
    let week: [PlanDay] = [.train(.sport("run")), .rest, .train(nil), .rest, .train(.sport("yoga")), .rest, .rest]
    try await signUp.savePlan(week)

    #expect(try await member.api.hasAgreedToAI())
    #expect(squad.name == "周三不练腿")
    #expect(squad.teammates.isEmpty)
    #expect(squad.weekDone == 0)
    #expect(try await member.api.mySquads().map(\.id) == [squad.id])
    let profile = try #require(try await member.api.me().profile)
    #expect(
        profile.character
            == MemberCharacter(
                nickname: try Nickname("小林"),
                look: CharacterLook(
                    persona: "shy", variants: ["body": "calico", "top": "warmup-tee"], colors: ["top": "#3A7BD5"])))
    let thisWeek = LocalDay(at: Date(), in: profile.timeZone).weekStart
    #expect(try await member.api.planTemplate() == week)
    #expect(try await member.api.weeklyPlan(weekStart: thisWeek).days == week)
    #expect(try await member.api.weeklyPlan(weekStart: thisWeek.adding(days: 21)).days == week)

    // 这周在哪练？: the squad trains on its pick at once, and a retry of it is fine.
    try await signUp.pickScene(.pool, for: squad.id)
    try await signUp.pickScene(.pool, for: squad.id)
    #expect(try await member.api.scene(of: squad.id).scene == .pool)
}

@Test func aFriendSeesTheInviteJoinsAndMeetsTheSquad() async throws {
    let stack = try LocalStack()
    let creator = try await stack.signedInMember()
    try await APISignUpService(api: creator.api).save(try character("阿杰", body: "shiba", persona: .energetic))
    try await APISignUpService(api: creator.api).agreeToAI()
    let made = try await APISignUpService(api: creator.api).create(named: try SquadName("早八健身"))
    let code = try InviteCode(try await creator.api.mySquads()[0].inviteCode)
    let friend = try await stack.signedInMember()
    let signUp = APISignUpService(api: friend.api)

    #expect(
        try await signUp.preview(code)
            == SquadPreview(
                code: code, name: "早八健身", memberCount: 1, isFull: false,
                looks: [
                    CharacterLook(
                        persona: "energetic", variants: ["body": "shiba", "top": "warmup-tee"],
                        colors: ["top": "#3A7BD5"])
                ]))
    try await signUp.agreeToAI()
    let joined = try await signUp.join(code)
    #expect(joined.id == made.id)
    #expect(
        joined.teammates == [
            Squadmate(
                id: creator.id, nickname: "阿杰",
                outfit: Outfit(
                    ["body": "shiba", "top": "warmup-tee"], colors: ["top": RGBAColor(red: 58, green: 123, blue: 213)]),
                persona: .energetic)
        ])
    // Joining again, after a lost answer, is the same squad.
    #expect(try await signUp.join(code).id == made.id)
    #expect(try await friend.api.mySquads().map(\.id) == [made.id])
}

@Test func savingTheCharacterKeepsTheRestOfTheProfile() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let zone = try #require(TimeZone(identifier: "America/Toronto"))
    _ = try await member.api.save(Profile(timeZone: zone, catchphrase: try Catchphrase("冲就完了")))

    try await APISignUpService(api: member.api).save(try character("豆豆", body: "bear", persona: .drama))

    let profile = try #require(try await member.api.me().profile)
    #expect(profile.timeZone == zone)
    #expect(profile.catchphrase == (try Catchphrase("冲就完了")))
    #expect(profile.character?.nickname == (try Nickname("豆豆")))
}

@Test func anInviteCodeNoSquadHasIsUnknown() async throws {
    let stack = try LocalStack()
    let signUp = APISignUpService(api: try await stack.signedInMember().api)
    let code = try InviteCode("ZZZZ2222")
    try await signUp.agreeToAI()

    await #expect(throws: SignUpError.unknownInvite) { try await signUp.preview(code) }
    await #expect(throws: SignUpError.unknownInvite) { try await signUp.join(code) }
}

@Test func aFourthSquadIsOneTooMany() async throws {
    let stack = try LocalStack()
    let signUp = APISignUpService(api: try await stack.signedInMember().api)
    try await signUp.agreeToAI()
    for name in ["一队", "二队", "三队"] { _ = try await signUp.create(named: try SquadName(name)) }

    await #expect(throws: SignUpError.tooManySquads) { try await signUp.create(named: try SquadName("四队")) }
}

@Test func noSquadWithoutAgreeingToAI() async throws {
    let stack = try LocalStack()
    let signUp = APISignUpService(api: try await stack.signedInMember().api)

    await #expect(throws: SignUpError.rejected) { try await signUp.create(named: try SquadName("一队")) }
    // Agreeing twice, after a lost answer, is fine.
    try await signUp.agreeToAI()
    try await signUp.agreeToAI()
    _ = try await signUp.create(named: try SquadName("一队"))
}

// The app's whole path, as `AppModel` composes it: a member signed in with no squad gets no
// home, signs up, lands on their squad's home and posts; signing out leaves nothing behind.

@MainActor private func home(_ member: SignedInMember, in directory: URL) -> TodayStore {
    TodayStore(
        backend: APICheckInBackend(api: member.api, directory: directory), outbox: DeviceOutbox(directory: directory),
        now: { Date() }, newID: { UUID() })
}

@MainActor @Test func aNewMemberSignsUpLandsOnTheirSquadAndPosts() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")

    let before = home(member, in: directory)
    await before.load()
    #expect(before.phase == .noSquad)

    let signUp = APISignUpService(api: member.api)
    try await signUp.save(try character("小林", body: "calico", persona: .shy))
    try await signUp.agreeToAI()
    let squad = try await signUp.create(named: try SquadName("周三不练腿"))
    try await signUp.savePlan(Array(repeating: .train(nil), count: 7))

    let today = home(member, in: directory)
    await today.load()
    #expect(today.phase == .current)
    #expect(today.home?.squad.id == squad.id)
    #expect(today.home?.today.members.map(\.character?.nickname.text) == ["小林"])
    guard case .posted = try await today.post(.trained(.sport("run"), nil, PostBody(photos: [], caption: "")))
    else { Issue.record("the post was queued, not saved"); return }
    #expect(today.myStatus == .trained)
}

@MainActor @Test func signingOutLeavesNothingOnThePhone() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    _ = try await stack.squad(of: member)
    let folders = MemberFolders(
        root: FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)"))
    let directory = folders.folder(for: member.id)
    await home(member, in: directory).load()
    #expect(await APICheckInBackend(api: member.api, directory: directory).savedHome() != nil)

    try await member.account.signOut()
    folders.forgetAll()

    #expect(await APICheckInBackend(api: member.api, directory: directory).savedHome() == nil)
    #expect(await DeviceOutbox(directory: directory).load().isEmpty)
    let after = home(member, in: directory)
    await after.load()
    #expect(after.phase == .signedOut)
}

@Test func aSignUpClosedAfterJoiningCarriesOnWithTheSquadAndTheCharacter() async throws {
    let stack = try LocalStack()
    let creator = try await stack.signedInMember()
    try await APISignUpService(api: creator.api).save(try character("阿杰", body: "shiba", persona: .energetic))
    try await APISignUpService(api: creator.api).agreeToAI()
    _ = try await APISignUpService(api: creator.api).create(named: try SquadName("早八健身"))
    let code = try InviteCode(try await creator.api.mySquads()[0].inviteCode)
    let friend = try await stack.signedInMember()
    let saved = try character("小林", body: "calico", persona: .shy)
    try await APISignUpService(api: friend.api).save(saved)
    try await APISignUpService(api: friend.api).agreeToAI()
    let joined = try await APISignUpService(api: friend.api).join(code)

    // The app was closed here; the next launch reads the same squad and character back.
    let resumed = try await APISignUpService(api: friend.api).resume(in: joined.id)

    #expect(resumed.squad == joined)
    #expect(resumed.character == saved)
}
