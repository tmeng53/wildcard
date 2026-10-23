import Contracts
import Foundation
import ScheduleDomain
import Testing

@testable import Backend

// 出赛表's adapter against the built API and local Supabase: who the poster is for, a week with
// the days checked in and the squad's count, and saving a plan and 饮食小目标.

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
    #expect(profile.timeZone.identifier == "UTC")
    #expect(profile.firstWeek == (try thisWeek))
}

@Test func thisWeekShowsTheDaysCheckedInAndTheSquadsCount() async throws {
    let stack = try LocalStack()
    let (member, backend) = try await scheduleMember(stack)
    let squad = try await stack.squad(of: member)
    let trained = try checkIn(by: member, to: squad, .trained(Training(activity: .sport(.run))))
    _ = try await member.api.save(trained)

    let week = try await backend.week(starting: trained.day.weekStart)

    #expect(week.marks[trained.day.weekday - 1] == .trained)
    #expect(week.marks.filter { $0 == .trained }.count == 1)
    #expect(week.plan.count == 7)
    #expect(week.titles.isEmpty)
    #expect(week.fuel.isEmpty)
    if trained.day.weekStart == (try thisWeek) {
        #expect(week.squad?.trained == 1)
    }
    #expect(try await backend.trainedDays() == 1)
}

@Test func aPastWeekHasNoSquadCountAndNoTitlesUntilTheAwards() async throws {
    let stack = try LocalStack()
    let (member, backend) = try await scheduleMember(stack)
    _ = try await stack.squad(of: member)

    let week = try await backend.week(starting: try thisWeek.adding(days: -7))

    #expect(week.squad == nil)
    #expect(week.titles.isEmpty)
    #expect(week.marks == Array(repeating: .none, count: 7))
}

@Test func nextWeeksPlanAndFoodGoalsAreSaved() async throws {
    let (_, backend) = try await scheduleMember(try LocalStack())
    let nextWeek = try thisWeek.adding(days: 7)
    let plan: [PlanDay] = [
        .train(.sport(.run)), .rest, .train(.custom(try CustomSport("飞盘"))), .train(nil), .rest, .rest,
        .train(.sport(.swim)),
    ]
    let goals: [FuelGoal] = [.suggested(.water), .own("少喝可乐")]

    #expect(try await backend.savePlan(plan, weekStart: nextWeek) == plan)
    try await backend.saveFuel(goals, weekStart: nextWeek)

    let week = try await backend.week(starting: nextWeek)
    #expect(week.plan == plan)
    #expect(week.fuel == goals)
    #expect(week.squad == nil)
}

@Test func thisWeeksFoodGoalsCantChange() async throws {
    let (_, backend) = try await scheduleMember(try LocalStack())

    await #expect(throws: ScheduleError.weekOver) {
        try await backend.saveFuel([.suggested(.breakfast)], weekStart: try thisWeek)
    }
}
