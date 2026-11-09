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
    let squad = try await signUp.create(named: try SquadName("早八健身"), daysPerMember: 3, timeZone: "America/New_York")
    let service = APIMeService(api: member.api)
    // 本周 is the squad's today's count for the member; how many days the plan holds depends on
    // the weekday the test runs, since a week counts only from the day the member joined.
    let week = try await member.api.today(of: squad.id).myWeek.week
    #expect(week.trainedDays == 0)
    let joinedAt = try #require(try await member.api.me().joinedAt)

    var overview = try await service.overview()
    // WARM-UP is out for a newcomer, its headphones boxed 2 练了 away; a store still to earn shows
    // no piece.
    let stock = try #require(overview.stock)
    #expect(stock.pieces.first { $0.id == "warmup-headphones" }?.state == .locked(toGo: 2))
    #expect(!stock.pieces.contains { $0.store == "deuce" })
    overview.stock = nil
    // The 出赛表 tile's week: the member's first, numbered 1, with nothing trained yet and today
    // marked once.
    let glance = try #require(overview.weekGlance)
    #expect(glance.number == 1)
    #expect(glance.days.count == 7 && !glance.days.contains { $0.mark == .trained })
    #expect(glance.days.filter(\.isToday).count == 1)
    overview.weekGlance = nil
    // 训练记录: the weeks ending with this one, empty so far.
    let record = try #require(overview.record)
    #expect(record.columns.count == TrainingRecord.weeks)
    #expect(record.columns.joined().allSatisfy { $0.level == .none })
    overview.record = nil
    #expect(
        overview
            == MeOverview(
                character: MeCharacter(nickname: "阿杰", outfit: Outfit(["body": "shiba"]), persona: .drama),
                joinedAt: joinedAt.date,
                counts: .zero, week: week, squadName: "早八健身", dailyPushOn: true, squadPlace: 1))

    try await service.setDailyPush(false)
    #expect(try await service.overview().dailyPushOn == false)
}

@Test func anEditedCharacterKeepsTheRestOfTheProfile() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let zone = try #require(TimeZone(identifier: "America/Toronto"))
    _ = try await member.api.save(
        Profile(timeZone: zone, catchphrase: try Catchphrase("冲就完了"), jerseyNumber: try JerseyNumber(7)))
    let service = APIMeService(api: member.api)

    try await service.save(MeCharacter(nickname: "豆豆", outfit: Outfit(["body": "bear"]), persona: .shy))

    let signedIn = try await member.api.me()
    let profile = try #require(signedIn.profile)
    #expect(profile.timeZone == zone)
    #expect(profile.catchphrase == (try Catchphrase("冲就完了")))
    #expect(profile.jerseyNumber?.text == "07")
    #expect(signedIn.joinedAt != nil)
    #expect(
        try await service.overview().character
            == MeCharacter(nickname: "豆豆", outfit: Outfit(["body": "bear"]), persona: .shy))
    await #expect(throws: MeError.rejected) {
        try await service.save(MeCharacter(nickname: "", outfit: Outfit(["body": "bear"]), persona: .shy))
    }
}

@Test func aPickedNumberStaysThroughACharacterEditAndTheSecondToJoinWearsTwoTillThen() async throws {
    let stack = try LocalStack()
    let captain = try await stack.signedInMember()
    let member = try await stack.signedInMember()
    _ = try await member.api.save(Profile(timeZone: .current, catchphrase: try Catchphrase("冲就完了")))
    _ = try await stack.squad(of: captain, member)
    let service = APIMeService(api: member.api)

    let before = try await service.overview()
    #expect(before.squadPlace == 2)
    #expect(before.jerseyNumber == nil)
    #expect(before.cardNumber?.text == "02")

    try await service.save(jerseyNumber: try JerseyNumber(23))
    try await service.save(MeCharacter(nickname: "豆豆", outfit: Outfit(["body": "bear"]), persona: .shy))

    let after = try await service.overview()
    #expect(after.cardNumber?.text == "23")
    #expect(try await member.api.me().profile?.catchphrase == (try Catchphrase("冲就完了")))
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

@Test func recordsNameTheSquadmateWhoTrainedTheSameDayAndCheeredTheMost() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let utc = try #require(TimeZone(identifier: "UTC"))
    let coco = MemberCharacter(
        nickname: try Nickname("Coco"), look: CharacterLook(persona: "shy", variants: ["body": "lop"], colors: [:]))
    _ = try await mate.api.save(Profile(timeZone: utc, character: coco))
    _ = try await member.api.save(Profile(timeZone: utc))
    let squad = try await stack.squad(of: member, mate)
    let mine = try checkIn(
        by: member, to: squad, .trained(Training(activity: .sport("run"), minutes: try WorkoutMinutes(40))))
    _ = try await member.api.save(mine)
    _ = try await mate.api.save(try checkIn(by: mate, to: squad, .trained(Training(activity: .sport("yoga")))))
    try await mate.api.react(try Emoji("🔥"), to: mine.id)

    let records = try await APIMeService(api: member.api).records()
    #expect(records.trainedDays == 1)
    #expect(records.minutes == 40)
    #expect(records.longestMinutes == 40)
    #expect(records.longestStreak?.days == 1)
    #expect(records.sports == [.init(activity: .sport("run"), days: 1)])
    #expect(records.hours.reduce(0, +) == 1)
    let partner = try #require(records.squad?.partner)
    #expect(partner.count == 1)
    #expect(partner.mate.member == mate.id)
    #expect(partner.mate.character?.nickname == "Coco")
    #expect(records.squad?.cheersReceived.count == 1)
    #expect(records.squad?.cheersReceived.top?.mate.member == mate.id)
    #expect(records.squad?.cheersGiven.count == 0)
}
