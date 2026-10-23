import Foundation

/// A squad's today, as the home screen shows it: where each member's day stands, today's
/// counts, the member's own 本周 x/y and the squad's week. The API works it out on each
/// member's own clock.
public struct SquadToday: Hashable, Sendable {
    public let squad: SquadID
    /// Everyone in the squad, the signed-in member included, in the home screen's order: first
    /// those who checked in today, by their first check-in; then those on a planned rest day;
    /// then everyone else.
    public var members: [SquadmateToday]
    public var today: TodayCounts
    /// The signed-in member's week.
    public var myWeek: MyWeek
    /// 本周小队训练 x/y: days trained over days planned, added up over the members.
    public var squadWeek: WeekCount

    public init(squad: SquadID, members: [SquadmateToday], today: TodayCounts, myWeek: MyWeek, squadWeek: WeekCount) {
        self.squad = squad
        self.members = members
        self.today = today
        self.myWeek = myWeek
        self.squadWeek = squadWeek
    }
}

/// One member's today in a squad.
public struct SquadmateToday: Hashable, Sendable {
    public let member: MemberID
    /// What their character shouts when the squad cheers a teammate's 练了; nil for their
    /// persona's own line.
    public let catchphrase: Catchphrase?
    /// Their nickname and character's look; nil until they make it in sign-up.
    public let character: MemberCharacter?
    /// Their own today, in their time zone, with the 3am grace.
    public let day: LocalDay
    public var training: TrainingStatus
    public var latestMeal: MealKind?
    /// Today is a rest day in their weekly plan, whatever they checked in.
    public let plannedRest: Bool
    /// When they first checked in today, of any kind.
    public var firstCheckInAt: Timestamp?

    public init(
        member: MemberID, catchphrase: Catchphrase?, character: MemberCharacter?, day: LocalDay,
        training: TrainingStatus,
        latestMeal: MealKind?,
        plannedRest: Bool, firstCheckInAt: Timestamp?
    ) {
        self.member = member
        self.catchphrase = catchphrase
        self.character = character
        self.day = day
        self.training = training
        self.latestMeal = latestMeal
        self.plannedRest = plannedRest
        self.firstCheckInAt = firstCheckInAt
    }
}

/// The two meals a check-in can be.
public enum MealKind: Hashable, Sendable {
    case healthyMeal
    case cheatMeal
}

/// How many members' today is each kind.
public struct TodayCounts: Hashable, Sendable {
    public var trained: Int
    /// A 请假条 and no 练了.
    public var disclaimer: Int
    /// On a planned rest day, with no 练了 or 请假条.
    public var resting: Int
    /// 全员上场: someone trained, and everyone who didn't is on a planned rest day.
    public var everyoneTrained: Bool

    public init(trained: Int, disclaimer: Int, resting: Int, everyoneTrained: Bool) {
        self.trained = trained
        self.disclaimer = disclaimer
        self.resting = resting
        self.everyoneTrained = everyoneTrained
    }
}

/// Days trained against days planned: 本周 x/y.
public struct WeekCount: Hashable, Sendable {
    /// Days with a 练了; several on one day count once.
    public var trainedDays: Int
    /// Training days in the plan.
    public var plannedDays: Int

    public init(trainedDays: Int, plannedDays: Int) {
        self.trainedDays = trainedDays
        self.plannedDays = plannedDays
    }
}

/// The signed-in member's week and lifetime.
public struct MyWeek: Hashable, Sendable {
    /// The week's Monday and Sunday.
    public let firstDay: LocalDay
    public let lastDay: LocalDay
    public var week: WeekCount
    /// Days ever with a 练了.
    public var lifetimeTrainedDays: Int

    public init(firstDay: LocalDay, lastDay: LocalDay, week: WeekCount, lifetimeTrainedDays: Int) {
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.week = week
        self.lifetimeTrainedDays = lifetimeTrainedDays
    }
}
