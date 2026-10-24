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
    meals: Bool = true, disclaimer: Bool = true
) throws -> WeekStory {
    WeekStory(
        status: status, squad: SquadID(UUID()), squadName: "晨跑五人组",
        week: Week(monday: try day(13), sunday: try day(19)),
        order: order,
        podium: podium ? Podium(champion: id(1), sides: [id(2), id(3), id(4)]) : nil,
        titles: titles ? [MemberTitles(member: id(1), titles: [.init(title: "早八战神")])] : [],
        myWeek: MyWeek(plan: 5, days: [], healthyMeals: 3, cheatMeals: 1, reactionsReceived: 12),
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
        case .hottest: "hottest"
        case .meals: "meals"
        case .bestDisclaimer: "bestDisclaimer"
        case .ending: "ending"
        }
    }
}

@Test func aReadyStoryPlaysTheAwardsFirstAndTheEndingLast() throws {
    #expect(
        ids(try story().pages) == ["podium", "titles", "myWeek", "hottest", "meals", "bestDisclaimer", "ending"])
}

@Test func theAIOrdersTheMiddleButTheEndingStaysLastAndNothingPlaysTwice() throws {
    let order: [PageID] = [.podium, .titles, .ending, .meals, .hottest, .meals, .myWeek]
    #expect(ids(try story(order: order).pages) == ["podium", "titles", "meals", "hottest", "myWeek", "ending"])
}

@Test func aPageWithNoDataIsLeftOut() throws {
    #expect(
        ids(try story(podium: false, meals: false, disclaimer: false).pages) == [
            "titles", "myWeek", "hottest", "ending",
        ])
    #expect(ids(try story(titles: false).pages).contains("titles") == false)
}

@Test func aPendingStoryWaitsOnlyOnItsTitles() throws {
    #expect(
        ids(try story(.pending).pages) == [
            "podium", "pending", "myWeek", "hottest", "meals", "bestDisclaimer", "ending",
        ])
}

@Test func thePodiumHasAtMostTwoSidesAndTheCastStartsWithIt() throws {
    let story = try story()
    #expect(story.podium?.sides == [id(2), id(3)])
    #expect(story.cast == [id(1), id(2), id(3), id(4)])
    #expect(story.firstTitle(of: id(1)) == "早八战神")
    #expect(story.firstTitle(of: id(2)) == nil)
}

@Test func anUnknownMoveCheers() throws {
    #expect(AwardMove(wire: "pump") == .pump)
    #expect(AwardMove(wire: "moonwalk") == .cheer)
    #expect(AwardMove.stack.solo == .cheer)
    #expect(AwardMove.wave.solo == .wave)
}

@Test func eachDayPlaysItsSportRestOrDisclaimerMove() throws {
    #expect(DayKind.trained("tennis").clip == .sport("tennis"))
    #expect(DayKind.trained(nil).clip == .sport(nil))
    #expect(DayKind.rest.clip?.name == "doze")
    #expect(DayKind.disclaimer.clip?.name == "flat")
    #expect(DayKind.none.clip == nil)
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
        week: Week(monday: try day(13), sunday: try day(19)), ending: Ending(done: 0, plan: 0))
    #expect(empty.isPublished == false)
}

@Test func aStoryWithItsAwardsOrWaitingForThemIsOut() throws {
    #expect(try story().isPublished)
    #expect(try story(.pending, titles: false).isPublished)
    // Awards given to nobody (no one had agreed to AI use) still leave the week's facts.
    #expect(try story(titles: false).isPublished)
}
