import APIContract
import AccountDomain
import Contracts
import Foundation
import ScheduleDomain
import Testing

@testable import Backend

// 出赛表's adapter against the built API and local Supabase: who the poster is for, a week with
// the days checked in, and saving a plan and 饮食小目标.

private func scheduleMember(_ stack: LocalStack) async throws -> (SignedInMember, APIScheduleBackend) {
    let member = try await stack.signedInMember()
    let character = MemberCharacter(
        nickname: try Nickname("小林"), look: CharacterLook(persona: "shy", variants: ["body": "calico"], colors: [:]))
    _ = try await member.api.save(Profile(timeZone: try #require(TimeZone(identifier: "UTC")), character: character))
    return (member, APIScheduleBackend(api: member.api))
}

private var thisWeek: LocalDay {
    get throws { LocalDay(at: Date(), in: try #require(TimeZone(identifier: "UTC"))).weekStart }
}

@Test func theProfileNamesTheMemberAndStartsAtTheirFirstWeek() async throws {
    let (_, backend) = try await scheduleMember(try LocalStack())

    let profile = try await backend.profile()

    #expect(profile.nickname == "小林")
    // Foundation on Linux names UTC "GMT", so compare the zones, not their names.
    #expect(profile.timeZone == (try #require(TimeZone(identifier: "UTC"))))
    #expect(profile.firstWeek == (try thisWeek))
    #expect(profile.look == CharacterLook(persona: "shy", variants: ["body": "calico"], colors: [:]))
}

@Test func thisWeekShowsTheDaysCheckedInAndTheSquadsCount() async throws {
    let stack = try LocalStack()
    let (member, backend) = try await scheduleMember(stack)
    let squad = try await stack.squad(of: member)
    let trained = try checkIn(by: member, to: squad, .trained(Training(activity: .sport("run"))))
    _ = try await member.api.save(trained)

    let week = try await backend.week(starting: trained.day.weekStart)

    #expect(week.marks[trained.day.weekday - 1] == .trained([.sport("run")]))
    #expect(week.marks.filter(\.isTrained).count == 1)
    #expect(week.plan.count == 7)
    #expect(week.titles.isEmpty)
    #expect(week.fuel.isEmpty)
}

@Test func aPastWeekHasNoTitlesUntilTheAwards() async throws {
    let stack = try LocalStack()
    let (member, backend) = try await scheduleMember(stack)
    _ = try await stack.squad(of: member)

    let week = try await backend.week(starting: try thisWeek.adding(days: -7))

    #expect(week.titles.isEmpty)
    #expect(week.marks == Array(repeating: .none, count: 7))
}

@Test func nextWeeksPlanAndFoodGoalsAreSaved() async throws {
    let (_, backend) = try await scheduleMember(try LocalStack())
    let nextWeek = try thisWeek.adding(days: 7)
    let plan: [PlanDay] = [
        .train(.sport("run")), .rest, .train(.custom(try CustomSport("飞盘"))), .train(nil), .rest, .rest,
        .train(.sport("swim")),
    ]
    let goals: [FuelGoal] = [.suggested(.water), .own("少喝可乐")]

    #expect(try await backend.savePlan(plan, weekStart: nextWeek) == plan)
    try await backend.saveFuel(goals, weekStart: nextWeek)

    let week = try await backend.week(starting: nextWeek)
    #expect(week.plan == plan)
    #expect(week.fuel == goals)
}

@Test func thisWeeksFoodGoalsChangeAndLastWeeksDont() async throws {
    let (_, backend) = try await scheduleMember(try LocalStack())

    try await backend.saveFuel([.suggested(.breakfast)], weekStart: try thisWeek)
    #expect(try await backend.week(starting: try thisWeek).fuel == [.suggested(.breakfast)])
    await #expect(throws: ScheduleError.weekOver) {
        try await backend.saveFuel([.suggested(.breakfast)], weekStart: try thisWeek.adding(days: -7))
    }
}

// The adapter's own rules, with no stack.

private func posted(_ entry: CheckIn.Entry, on day: LocalDay, at milliseconds: Int64 = 0) throws -> CheckIn {
    CheckIn(
        id: CheckInID(UUID()), member: MemberID(UUID()), day: day,
        createdAt: Timestamp(millisecondsSince1970: milliseconds),
        audience: try Audience([SquadID(UUID())]), entry: entry)
}

@Test func aDayWithATrainingAndAnExcuseCountsAsTrained() throws {
    let monday = try LocalDay(year: 2026, month: 10, day: 19)
    let checkIns = [
        try posted(.disclaimer(try Disclaimer("下雨")), on: monday),
        try posted(.trained(Training(activity: .sport("run"))), on: monday),
        try posted(.disclaimer(try Disclaimer("加班")), on: monday.adding(days: 2)),
        try posted(.healthyMeal(Meal()), on: monday.adding(days: 3)),
        try posted(.trained(Training(activity: .sport("swim"))), on: monday.adding(days: 7)),
    ]

    #expect(
        APIScheduleBackend.marks(of: checkIns, weekStart: monday) == [
            .trained([.sport("run")]), .none, .disclaimer, .none, .none, .none, .none,
        ])
}

@Test func aDayTrainedTwiceKeepsBothSportsLatestLast() throws {
    let monday = try LocalDay(year: 2026, month: 10, day: 19)
    let checkIns = [
        try posted(.trained(Training(activity: .sport("tennis"))), on: monday, at: 2_000),
        try posted(.trained(Training(activity: .sport("run"))), on: monday, at: 1_000),
    ]

    #expect(
        APIScheduleBackend.marks(of: checkIns, weekStart: monday).first == .trained([.sport("run"), .sport("tennis")]))
}

@Test func eachRefusalMeansSomethingOnTheSchedule() {
    #expect(ScheduleError(.refused(.weekClosed)) == .weekOver)
    #expect(ScheduleError(.refused(.planDayStarted)) == .dayStarted)
    #expect(ScheduleError(.refused(.squadFull)) == .refused)
    #expect(ScheduleError(.unreadableResponse) == .refused)
    #expect(ScheduleError(.unavailable) == .notSent)
    #expect(ScheduleError(.account(.signedOut)) == .signedOut)
    #expect(ScheduleError(.account(.credentialRejected)) == .signedOut)
    #expect(ScheduleError(.account(.unavailable)) == .notSent)
}

@Test func aStoryTitleKeepsItsBadgeAndOneFromAnOlderServerGetsTheDefault() throws {
    let json = Data(
        """
        [
          {"title": "网球担当", "speech": "三次站上网球场", "move": "pump",
           "badge": {"shape": "shield", "colour": "tennis", "tone": "#4F6B22", "glyph": "tennisball.fill"}},
          {"title": "早起冠军", "speech": "三次在七点前打卡", "move": "cheer"}
        ]
        """.utf8)
    let titles = try JSONDecoder().decode([Components.Schemas.StoryTitle].self, from: json)

    #expect(
        APIScheduleBackend.awardTitles(titles) == [
            AwardTitle(
                title: "网球担当", speech: "三次站上网球场",
                badge: TitleBadge(shape: "shield", colour: "tennis", tone: "#4F6B22", glyph: "tennisball.fill")),
            AwardTitle(
                title: "早起冠军", speech: "三次在七点前打卡",
                badge: TitleBadge(shape: "circle", colour: "gym", glyph: "star.fill")),
        ])
}
