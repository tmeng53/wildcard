import Contracts
import Foundation
import Testing

@testable import RecapDomain

private func id(_ number: Int) -> MemberID {
    MemberID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID())
}

private func post(_ number: Int, by member: Int, on date: Int, _ entry: CheckIn.Entry) throws -> CheckIn {
    CheckIn(
        id: CheckInID(UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", number)) ?? UUID()),
        member: id(member), day: try LocalDay(year: 2026, month: 10, day: date),
        createdAt: Timestamp(millisecondsSince1970: Int64(number)), audience: try Audience([SquadID(UUID())]),
        entry: entry)
}

private func ran() -> CheckIn.Entry { .trained(Training(activity: .sport(.run))) }

private func story(titles: [MemberTitles] = []) throws -> WeekStory {
    WeekStory(
        status: .ready, squad: SquadID(UUID()), squadName: "晨跑五人组",
        week: Week(
            monday: try LocalDay(year: 2026, month: 10, day: 12), sunday: try LocalDay(year: 2026, month: 10, day: 18)),
        titles: titles)
}

private func facts(
    planCompleted: [Int] = [], crown: [Int] = [], best: WeekFacts.Best? = nil, trained: Int = 0, planned: Int = 0,
    myPlanned: Int = 0, checkIns: [CheckIn] = [], plan: [PlanDay]? = nil
) -> WeekFacts {
    WeekFacts(
        viewer: id(1), planCompleted: planCompleted.map(id), crown: crown.map(id), bestDisclaimer: best,
        squadTrained: trained, squadPlanned: planned, myPlanned: myPlanned, myReactionsReceived: 4, checkIns: checkIns,
        plan: plan)
}

@Test func thePodiumHasTheCrownInTheMiddleAndTheOthersWhoFinishedBesideIt() throws {
    let titles = [
        MemberTitles(member: id(3), titles: [.init(title: "早八战神", speech: "闹钟都怕她", move: .pose)]),
        MemberTitles(member: id(2), titles: [.init(title: "稳", move: .wave)]),
    ]

    let podium = try story(titles: titles).filled(with: facts(planCompleted: [2, 3, 4], crown: [3])).podium

    #expect(
        podium == Podium(champion: id(3), sides: [id(2), id(4)], speech: "闹钟都怕她", championMove: .pose, sideMove: .wave))
}

@Test func nobodyFinishingTheirPlanLeavesThePodiumOut() throws {
    #expect(try story().filled(with: facts()).podium == nil)
}

@Test func myWeekPlaysEachDayFromMyCheckInsAndPlan() throws {
    let plan: [PlanDay] = [.train(nil), .rest, .train(nil), .train(nil), .rest, .train(nil), .rest]
    let checkIns = [
        try post(1, by: 1, on: 12, ran()),
        try post(2, by: 1, on: 14, .disclaimer(try Disclaimer("下雨"))),
        try post(3, by: 1, on: 15, .trained(Training(activity: .custom(try CustomSport("飞盘"))))),
        try post(4, by: 1, on: 15, .healthyMeal(Meal())),
        try post(5, by: 2, on: 13, ran()),
    ]

    let week = try #require(try story().filled(with: facts(myPlanned: 4, checkIns: checkIns, plan: plan)).myWeek)

    #expect(week.days.map(\.kind) == [.trained(.run), .rest, .disclaimer, .trained(nil), .rest, .none, .rest])
    #expect(week.plan == 4)
    #expect(week.healthyMeals == 1)
    #expect(week.cheatMeals == 0)
    #expect(week.reactionsReceived == 4)
}

@Test func eachEaterEatsWhatTheyLoggedMoreOf() throws {
    let checkIns = [
        try post(1, by: 1, on: 12, .healthyMeal(Meal())),
        try post(2, by: 2, on: 12, .cheatMeal(Meal())),
        try post(3, by: 2, on: 13, .cheatMeal(Meal())),
        try post(4, by: 2, on: 14, .healthyMeal(Meal())),
        try post(5, by: 3, on: 14, ran()),
    ]

    let meals = try story().filled(with: facts(checkIns: checkIns)).meals

    #expect(
        meals
            == Meals(
                healthy: 2, cheat: 2,
                eaters: [.init(member: id(1), more: .healthy), .init(member: id(2), more: .cheat)]))
}

@Test func theBest请假条TakesItsWordsFromTheSquadsCheckIns() throws {
    let note = try post(7, by: 2, on: 16, .disclaimer(try Disclaimer("教练说要循序渐进")))

    let best = try story().filled(with: facts(best: .init(checkIn: note.id, reactions: 6), checkIns: [note]))
        .bestDisclaimer

    #expect(best == BestDisclaimer(checkIn: note.id, author: id(2), text: "教练说要循序渐进", reactions: 6))
}

@Test func theEndingCountsTheSquadsDaysAndIsLeftOutWhenNobodyTrained() throws {
    #expect(try story().filled(with: facts(trained: 19, planned: 22)).ending == Ending(done: 19, plan: 22))
    #expect(try story().filled(with: facts(planned: 22)).ending == nil)
    #expect(try story().filled(with: facts(myPlanned: 5, plan: [.rest])).myWeek == nil)
}

@Test func aFilledStoryPlaysEveryPageInOrder() throws {
    let checkIns = [try post(1, by: 1, on: 12, ran()), try post(2, by: 1, on: 12, .cheatMeal(Meal()))]
    let titles = [MemberTitles(member: id(1), titles: [.init(title: "早八战神")])]

    let pages = try story(titles: titles)
        .filled(with: facts(planCompleted: [1], crown: [1], trained: 1, planned: 1, myPlanned: 1, checkIns: checkIns))
        .pages

    #expect(pages.count == 5)
    if case .podium = pages.first {} else { Issue.record("the podium opens the story") }
    if case .ending = pages.last {} else { Issue.record("the ending closes the story") }
}
