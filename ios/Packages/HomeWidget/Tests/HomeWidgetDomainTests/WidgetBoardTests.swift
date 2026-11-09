import CheckInDomain
import Contracts
import Foundation
import HealthDomain
import HomeWidgetDomain
import Testing

private func id(_ number: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", number))") ?? UUID()
}

private let viewer = MemberID(id(1))
private let mate = MemberID(id(2))
private let resting = MemberID(id(3))
private let squadID = SquadID(id(10))
private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
/// Tuesday 2026-10-20, 10:00 in Los Angeles.
private let tuesdayMorning = Date(timeIntervalSince1970: 1_792_515_600)
private let tuesday = LocalDay(at: tuesdayMorning, in: losAngeles)

private func row(_ member: MemberID, _ training: TrainingStatus, on day: LocalDay = tuesday, rest: Bool = false)
    -> SquadmateToday
{
    SquadmateToday(
        member: member, catchphrase: nil, character: nil, day: day, training: training, latestMeal: nil,
        plannedRest: rest, firstCheckInAt: nil)
}

/// Mate trained, I haven't checked in, the third rests by plan; I trained once this week.
private func home(members: [SquadmateToday]? = nil, checkIns: [CheckIn] = []) -> Home {
    let today = SquadToday(
        squad: squadID,
        members: members ?? [row(mate, .trained), row(viewer, .notCheckedIn), row(resting, .notCheckedIn, rest: true)],
        today: TodayCounts(trained: 1, disclaimer: 0, resting: 1, everyoneTrained: false),
        myWeek: MyWeek(
            firstDay: tuesday.weekStart, lastDay: tuesday.weekStart.adding(days: 6),
            week: WeekCount(trainedDays: 1, plannedDays: 4)),
        squadWeek: WeekCount(trainedDays: 15, plannedDays: 24))
    let plan = try? WeeklyPlan(
        member: viewer, weekStart: tuesday.weekStart,
        days: [.train(nil), .train(nil), .rest, .train(nil), .rest, .train(nil), .rest])
    return Home(
        member: viewer, timeZone: losAngeles,
        squad: Squad(
            id: squadID, name: "周三不练腿俱乐部", inviteCode: "K7M2QX9P", members: [mate, viewer, resting], captain: viewer),
        today: today, plan: plan ?? { fatalError("a seven-day plan") }(), checkIns: checkIns)
}

@Test func countsTheWeeksLikeTheSquadCard() {
    let board = WidgetBoard(home: home(), day: tuesday)
    #expect(board.squadName == "周三不练腿俱乐部")
    #expect(board.squad == WeekCount(trainedDays: 15, plannedDays: 24))
    #expect(board.mine == WeekCount(trainedDays: 1, plannedDays: 4))
    #expect(board.week.today == 1)
    #expect(board.week.days == [.open, .open, .restDay, .open, .restDay, .open, .restDay])
}

@Test func ringsEachMateForToday() {
    let board = WidgetBoard(home: home(), day: tuesday)
    #expect(board.mates.map(\.status) == [.checkedIn, .notYet, .restDay])
    #expect(board.mates.map(\.isMe) == [false, true, false])
    #expect(board.checkedInToday == 1)
}

@Test func aTapOpensCheckInUntilIHaveCheckedIn() {
    #expect(WidgetBoard(home: home(), day: tuesday).weekLink == .checkIn)
    let done = home(members: [row(mate, .trained), row(viewer, .disclaimer), row(resting, .notCheckedIn, rest: true)])
    #expect(WidgetBoard(home: done, day: tuesday).weekLink == .today)
}

@Test func aCopyFromYesterdayStartsTodayOpen() {
    // Thursday, a training day in my plan.
    let thursday = tuesday.adding(days: 2)
    let board = WidgetBoard(home: home(members: [row(mate, .trained), row(viewer, .trained)]), day: thursday)
    #expect(board.mates.allSatisfy { $0.status == .notYet })
    #expect(board.myStatus == .notCheckedIn)
    #expect(board.week.today == 3)
}

@Test func aMateBehindMeInTimeCountsTheirOwnToday() {
    // A fresh copy: my row is today, the mate's is their Monday on a clock behind mine.
    let board = WidgetBoard(
        home: home(members: [row(mate, .trained, on: tuesday.adding(days: -1)), row(viewer, .notCheckedIn)]),
        day: tuesday)
    #expect(board.mates.map(\.status) == [.checkedIn, .notYet])
    #expect(board.checkedInToday == 1)
}

@Test func looksAgainInHalfAnHourOrAtMidnight() {
    #expect(WidgetBoard.nextLook(after: tuesdayMorning, in: losAngeles) == tuesdayMorning.addingTimeInterval(1800))
    // 23:50 in Los Angeles: midnight comes first.
    let lateNight = tuesdayMorning.addingTimeInterval(13 * 3600 + 50 * 60)
    #expect(WidgetBoard.nextLook(after: lateNight, in: losAngeles) == lateNight.addingTimeInterval(600))
}

@Test func linksGoThereAndBack() {
    for link in WidgetLink.allCases {
        #expect(WidgetLink(url: link.url) == link)
    }
    #expect(WidgetLink.checkIn.url.absoluteString == "wildcard://widget/check-in")
    #expect(WidgetLink(url: URL(string: "https://wildcardsquad.com/join/K7M2QX9P") ?? WidgetLink.today.url) == nil)
}

/// A run in Health that ended `hoursBefore` Tuesday 10:00 in Los Angeles.
private func run(_ id: String, endedHoursBefore hours: Double) -> ImportedWorkout {
    let end = Timestamp(tuesdayMorning.addingTimeInterval(-hours * 3600))
    return ImportedWorkout(
        workout: Workout(
            source: WorkoutSource(provider: WorkoutSource.appleHealth, id: id),
            startedAt: Timestamp(millisecondsSince1970: end.millisecondsSince1970 - 1_920_000), endedAt: end,
            summary: WorkoutSummary(durationSec: 1920, distanceM: 5200)),
        activity: .sport("run"))
}

/// My 训练 posted from `workout` on Tuesday.
private func posted(_ workout: ImportedWorkout, by member: MemberID = viewer) -> CheckIn {
    let audience = try? Audience([squadID])
    return CheckIn(
        id: CheckInID(id(50)), member: member, day: tuesday, createdAt: Timestamp(tuesdayMorning),
        audience: audience ?? { fatalError("one squad") }(),
        entry: .trained(Training(activity: .sport("run"), minutes: workout.minutes, workout: workout.workout)))
}

@Test func offersTodaysNewestWorkoutNotPostedOrPutAway() {
    let early = run("early", endedHoursBefore: 3)
    let late = run("late", endedHoursBefore: 1)
    // Monday evening in Los Angeles: yesterday's, never offered.
    let yesterday = run("yesterday", endedHoursBefore: 14)
    let offered = WidgetBoard(home: home(), day: tuesday, health: [early, yesterday, late])
    #expect(offered.workout?.id.id == "late")
    // Posted by me: the next one down; a teammate's post of the same id changes nothing.
    #expect(
        WidgetBoard(home: home(checkIns: [posted(late)]), day: tuesday, health: [early, late]).workout?.id.id == "early"
    )
    #expect(
        WidgetBoard(home: home(checkIns: [posted(late, by: mate)]), day: tuesday, health: [late]).workout?.id.id
            == "late")
    // Put away from 今天's card on this phone.
    #expect(WidgetBoard(home: home(), day: tuesday, health: [late], putAway: [late.id]).workout == nil)
    #expect(WidgetBoard(home: home(), day: tuesday, health: [yesterday]).workout == nil)
    // A sport the list has nothing like is picked by hand in the app.
    let unlisted = ImportedWorkout(workout: late.workout, activity: nil)
    #expect(WidgetBoard(home: home(), day: tuesday, health: [early, unlisted]).workout?.id.id == "early")
}
