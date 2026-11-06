import Contracts
import DesignSystem
import Foundation
import Testing

@testable import RecapDomain

private func id(_ number: Int) -> MemberID {
    MemberID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID())
}

private func day(_ number: Int) throws -> LocalDay {
    try LocalDay(year: 2026, month: 10, day: number)
}

private let checkIn = CheckInID(UUID())

private func story(
    _ status: WeekStory.Status = .ready, order: [PageID]? = nil, podium: Bool = true, titles: Bool = true,
    meals: Bool = true, disclaimer: Bool = true, squadWeek: Bool = true
) throws -> WeekStory {
    WeekStory(
        status: status, squad: SquadID(UUID()), squadName: "晨跑五人组",
        week: Week(monday: try day(13), sunday: try day(19)), scene: .gym, squadmates: [],
        order: order,
        podium: podium ? Podium(champion: id(1), sides: [id(2), id(3), id(4)]) : nil,
        titles: titles ? [MemberTitles(member: id(1), titles: [.init(title: "早八战神")])] : [],
        myWeek: MyWeek(plan: 5, days: [], healthyMeals: 3, cheatMeals: 1, reactionsReceived: 12),
        squadWeek: squadWeek ? SquadWeek(members: [.init(member: id(1), days: [.trained("run")])]) : nil,
        hottest: Hottest(checkIn: checkIn, day: try day(16), kind: .trained, reactions: []),
        meals: meals ? Meals(healthy: 14, cheat: 5, eaters: []) : nil,
        bestDisclaimer: disclaimer
            ? BestDisclaimer(checkIn: checkIn, author: id(4), text: "教练说要循序渐进", reactions: 6) : nil,
        ending: Ending(done: 23, plan: 22))
}

private func ids(_ pages: [StoryPage]) -> [String] {
    pages.map {
        switch $0 {
        case .pending: "pending"
        case .podium: "podium"
        case .titles: "titles"
        case .myWeek: "myWeek"
        case .squadWeek: "squadWeek"
        case .hottest: "hottest"
        case .meals: "meals"
        case .bestDisclaimer: "bestDisclaimer"
        case .ending: "ending"
        }
    }
}

@Test func aReadyStoryPlaysTheAwardsFirstAndTheEndingLast() throws {
    #expect(
        ids(try story().pages) == [
            "podium", "titles", "myWeek", "squadWeek", "hottest", "meals", "bestDisclaimer", "ending",
        ])
}

@Test func theAIOrdersTheMiddleButTheEndingStaysLastAndNothingPlaysTwice() throws {
    let order: [PageID] = [.podium, .titles, .ending, .meals, .hottest, .meals, .myWeek]
    #expect(
        ids(try story(order: order).pages) == [
            "podium", "titles", "meals", "hottest", "myWeek", "squadWeek", "ending",
        ])
}

@Test func theSquadsWeekFollowsYourWeekWhereverItGoes() throws {
    let order: [PageID] = [.myWeek, .podium, .ending]
    #expect(ids(try story(order: order).pages) == ["myWeek", "squadWeek", "podium", "ending"])
    let withoutYours: [PageID] = [.podium, .meals]
    #expect(ids(try story(order: withoutYours).pages) == ["podium", "meals", "squadWeek", "ending"])
    #expect(ids(try story(squadWeek: false).pages).contains("squadWeek") == false)
}

@Test func theSquadsWeekAddsUpDaysAndRanksSports() {
    let week = SquadWeek(members: [
        .init(member: id(1), days: [.trained("run"), .rest, .trained("yoga"), .trained("run"), .none]),
        .init(member: id(2), days: [.trained("yoga"), .trained(nil), .disclaimer, .trained("yoga")]),
        .init(member: id(3), days: [.rest, .none]),
    ])
    #expect(week.trainedDays == 6)
    #expect(week.sports.map(\.sport) == ["yoga", "run"])
    #expect(week.sports.map(\.days) == [3, 2])
    #expect(week.disclaimers == SquadWeek.Disclaimers(days: 1, most: id(2)))
}

@Test func theSquadsWeekFindsItsFunNumbers() {
    let week = SquadWeek(members: [
        .init(
            member: id(1),
            days: [.trained("run"), .trained("run"), .trained("yoga"), .rest, .trained("run"), .none, .none],
            minutes: [30, nil, 45, nil, 60, nil, nil], reactionsReceived: 3),
        .init(
            member: id(2),
            days: [.none, .trained("run"), .trained(nil), .trained("run"), .trained("run"), .none, .none],
            minutes: [nil, 90, nil, nil, nil, nil, nil], reactionsReceived: 5),
        .init(
            member: id(3), days: [.none, .none, .trained("yoga"), .none, .none, .none, .none],
            minutes: [nil, nil, 20, nil, nil, nil, nil]),
    ])
    #expect(week.bestDay == SquadWeek.BestDay(weekday: 2, members: 3))
    #expect(week.longestStreak == SquadWeek.Streak(member: id(2), days: 4, from: 1))
    #expect(week.longestStreak?.through == 4)
    #expect(week.reactions == 8)
    #expect(week.disclaimers == nil)
    #expect(week.time == SquadWeek.TrainingTime(minutes: 245, longest: .init(member: id(2), minutes: 90)))
    #expect(week.members(training: ["run"]) == [id(1), id(2)])
    #expect(week.members(training: ["yoga"]) == [id(1), id(3)])
    #expect(week.members(training: ["run", "yoga"]) == [id(1), id(2), id(3)])
    #expect(week.members(training: ["swim"]) == [])
    #expect(week.members(trainedOn: 2) == [id(1), id(2), id(3)])
    #expect(week.members(trainedOn: 0) == [id(1)])
    #expect(week.members(trainedOn: 5) == [])
}

@Test func aFewMinutesOrOneDayInARowAreNoFunNumber() {
    let week = SquadWeek(members: [
        .init(member: id(1), days: [.trained("run"), .rest, .trained("run"), .none], minutes: [40]),
        .init(member: id(2), days: [.none, .trained("yoga"), .none, .trained("yoga")]),
    ])
    #expect(week.bestDay == SquadWeek.BestDay(weekday: 0, members: 1))
    #expect(week.longestStreak == nil)
    #expect(week.reactions == 0)
    #expect(week.time == nil)
}

@Test func aPageWithNoDataIsLeftOut() throws {
    #expect(
        ids(try story(podium: false, meals: false, disclaimer: false).pages) == [
            "titles", "myWeek", "squadWeek", "hottest", "ending",
        ])
    #expect(ids(try story(titles: false).pages).contains("titles") == false)
}

@Test func aPendingStoryWaitsOnlyOnItsTitles() throws {
    #expect(
        ids(try story(.pending).pages) == [
            "podium", "pending", "myWeek", "squadWeek", "hottest", "meals", "bestDisclaimer", "ending",
        ])
}

@Test func thePodiumHasAtMostTwoSidesAndTheCastStartsWithIt() throws {
    let story = try story()
    #expect(story.podium?.sides == [id(2), id(3)])
    #expect(story.cast == [id(1), id(2), id(3), id(4)])
    #expect(story.firstTitle(of: id(1)) == "早八战神")
    #expect(story.firstTitle(of: id(2)) == nil)
}

@Test func onlyThoseOnThePodiumCarryThePlanDoneMark() {
    let podium = Podium(champion: id(1), sides: [id(2), id(3), id(4)], planDone: [id(1), id(3), id(4)])
    #expect(podium.planDone == [id(1), id(3)])
}

/// Any move id the API sends is kept as it is, so new moves need no app change; the art plays
/// the cheer for one it doesn't have (StoryArtTests).
@Test func aMoveKeepsItsId() throws {
    #expect(AwardMove(wire: "pump") == .pump)
    #expect(AwardMove(wire: "chin-up").rawValue == "chin-up")
    #expect(AwardMove(wire: "swim").solo.rawValue == "swim")
    #expect(AwardMove.stack.solo == .cheer)
    #expect(AwardMove.wave.solo == .wave)
}

/// Beside the hottest post: the AI's move, else a 练了's own sport move, else the cheer.
@Test func theHottestPostPlaysItsSportUnlessTheAIPicked() throws {
    let swum = Hottest(checkIn: checkIn, day: try day(16), kind: .trained, sport: "swim", reactions: [])
    #expect(swum.clip == .sport("swim"))
    let picked = Hottest(
        checkIn: checkIn, day: try day(16), kind: .trained, sport: "swim", reactions: [], move: .pose)
    #expect(picked.clip == .award(.pose))
    let meal = Hottest(checkIn: checkIn, day: try day(16), kind: .healthyMeal, reactions: [])
    #expect(meal.clip == .award(.cheer))
}

@Test func yourWeekPlaysTheSportYouTrainedMost() throws {
    let days: [DayKind] = [.trained("tennis"), .rest, .trained("run"), .trained("run"), .disclaimer]
    let week = MyWeek(
        plan: 4, days: try days.enumerated().map { .init(day: try day(13 + $0.offset), kind: $0.element) },
        healthyMeals: 0, cheatMeals: 0, reactionsReceived: 0)
    #expect(week.trainedDays == 3)
    #expect(week.topSport.weekClip == .sport("run"))
    #expect(week.standsOn == 3)
    let rested = MyWeek(
        plan: 4, days: [.init(day: try day(13), kind: .rest), .init(day: try day(14), kind: .trained(nil))],
        healthyMeals: 0, cheatMeals: 0, reactionsReceived: 0)
    #expect(rested.topSport.weekClip == .award(.cheer))
    #expect(rested.standsOn == 1)
    #expect(StoryClip.eat(.cheat).name == "eat-treat")
    #expect(StoryClip.tossFlyer.name == "toss-flyer")
}

@Test func theFinaleFollowsTheResultAndNeedsTwoToStack() throws {
    #expect(Ending(done: 23, plan: 22, move: .stack).finale(castSize: 5) == .stack)
    #expect(Ending(done: 23, plan: 22, move: .stack).finale(castSize: 1) == .pump)
    #expect(Ending(done: 23, plan: 22, move: .warmup).finale(castSize: 5) == .pump)
    #expect(Ending(done: 19, plan: 22, move: .stack).finale(castSize: 5) == .warmup)
    #expect(Ending(done: 19, plan: 22, move: .stretch).finale(castSize: 5) == .stretch)
    #expect(Ending(done: 19, plan: 22).finale(castSize: 5) == .warmup)
}

@Test func theEndingCountsWhatIsMissingAndFillsItsBarToFull() throws {
    #expect(Ending(done: 19, plan: 22).isHit == false)
    #expect(Ending(done: 19, plan: 22).shortBy == 3)
    #expect(Ending(done: 23, plan: 22).isHit)
    #expect(Ending(done: 23, plan: 22).shortBy == 0)
    #expect(Ending(done: 23, plan: 22).fraction == 1)
    #expect(Ending(done: 11, plan: 22).fraction == 0.5)
}

@Test func myWeekCountsTrainedDays() throws {
    let week = MyWeek(
        plan: 5,
        days: [
            .init(day: try day(13), kind: .trained("run")), .init(day: try day(14), kind: .trained(nil)),
            .init(day: try day(15), kind: .rest), .init(day: try day(16), kind: .disclaimer),
            .init(day: try day(17), kind: .none),
        ], healthyMeals: 0, cheatMeals: 0, reactionsReceived: 0)
    #expect(week.trainedDays == 2)
}

@Test func aWeekNobodyCheckedInHasNoRecap() throws {
    let empty = WeekStory(
        status: .ready, squad: SquadID(UUID()), squadName: "晨跑五人组",
        week: Week(monday: try day(13), sunday: try day(19)), scene: .gym, squadmates: [],
        ending: Ending(done: 0, plan: 0))
    #expect(empty.isPublished == false)
}

@Test func aStoryWithNoPageAtAllIsNotOut() throws {
    // The shape behind a crash in build 5.1: the player can't start on no pages, so the shelf
    // opens only stories that came out.
    let blank = WeekStory(
        status: .ready, squad: SquadID(UUID()), squadName: "晨跑五人组",
        week: Week(monday: try day(13), sunday: try day(19)), scene: .gym, squadmates: [])
    #expect(blank.pages.isEmpty)
    #expect(blank.isPublished == false)
}

@Test func aStoryWithItsAwardsOrWaitingForThemIsOut() throws {
    #expect(try story().isPublished)
    #expect(try story(.pending, titles: false).isPublished)
    // Awards given to nobody (no one had agreed to AI use) still leave the week's facts.
    #expect(try story(titles: false).isPublished)
}

@Test func myWeekFindsItsStreakTimeAndTopSport() throws {
    let kinds: [(DayKind, Int?)] = [
        (.trained("run"), 30), (.rest, 99), (.trained("strength"), 80), (.trained("run"), 80),
        (.disclaimer, nil), (.trained("yoga"), nil), (.none, nil),
    ]
    let week = MyWeek(
        plan: 5,
        days: try kinds.enumerated().map {
            .init(day: try day(13 + $0.offset), kind: $0.element.0, minutes: $0.element.1)
        }, healthyMeals: 3, cheatMeals: 1, reactionsReceived: 9)
    #expect(week.days[1].minutes == nil)
    #expect(week.longestStreak == MyWeek.Streak(days: 2, from: 2))
    #expect(week.longestStreak?.through == 3)
    #expect(week.time == MyWeek.TrainingTime(minutes: 190, longestDay: 2, longestMinutes: 80))
    #expect(week.topSportDays == SquadWeek.SportDays(sport: "run", days: 2))
}

@Test func myWeekLeavesOutAStreakOfOneAndTooFewMinutes() throws {
    let kinds: [(DayKind, Int?)] = [(.trained("run"), 45), (.rest, nil), (.trained("run"), nil), (.trained(nil), nil)]
    let week = MyWeek(
        plan: 3,
        days: try kinds.enumerated().map {
            .init(day: try day(13 + $0.offset), kind: $0.element.0, minutes: $0.element.1)
        }, healthyMeals: 0, cheatMeals: 0, reactionsReceived: 0)
    #expect(week.longestStreak == MyWeek.Streak(days: 2, from: 2))
    #expect(week.time == nil)
    let single = MyWeek(
        plan: 3, days: [.init(day: try day(13), kind: .trained("run"), minutes: 20)],
        healthyMeals: 0, cheatMeals: 0, reactionsReceived: 0)
    #expect(single.longestStreak == nil)
    #expect(single.time == MyWeek.TrainingTime(minutes: 20, longestDay: 0, longestMinutes: 20))
}
