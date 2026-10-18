import Testing
import Contracts
import CheckInDomain

// MARK: - Day status

@Test func severalWorkoutsOnOneDayCountOnce() {
    let log = CheckInLog(member: tracy, checkIns: [
        checkIn("trained", on: "2026-10-19"), checkIn("trained", on: "2026-10-19"), checkIn("trained", on: "2026-10-20"),
    ])
    #expect(log.lifetimeTrainedDays == 2)
}

@Test func trainingAfterADisclaimerMakesTheDayTrained() {
    let log = CheckInLog(member: tracy, checkIns: [
        checkIn("disclaimer", on: "2026-10-19"), checkIn("trained", on: "2026-10-19"),
    ])
    #expect(log.training(on: day("2026-10-19")) == .trained)
    // The 免责声明 stays in the log for the feed.
    #expect(log.checkIns.count == 2)
}

@Test func mealsDontChangeTheTrainingStatus() {
    let log = CheckInLog(member: tracy, checkIns: [
        checkIn("healthy", on: "2026-10-19"), checkIn("cheat", on: "2026-10-19"), checkIn("disclaimer", on: "2026-10-20"),
    ])
    #expect(log.training(on: day("2026-10-19")) == .notCheckedIn)
    #expect(log.training(on: day("2026-10-20")) == .disclaimer)
    #expect(log.lifetimeTrainedDays == 0)
}

@Test func onlyHealthyMealsCountAsHealthy() {
    let log = CheckInLog(member: tracy, checkIns: [checkIn("cheat", on: "2026-10-19"), checkIn("healthy", on: "2026-10-20")])
    #expect(!log.hadHealthyMeal(on: day("2026-10-19")))
    #expect(log.hadHealthyMeal(on: day("2026-10-20")))
}

@Test func logKeepsOnlyItsMembersCheckIns() {
    let log = CheckInLog(member: tracy, checkIns: [checkIn("trained", on: "2026-10-19", by: coco)])
    #expect(log.checkIns.isEmpty)
    #expect(log.training(on: day("2026-10-19")) == .notCheckedIn)
}

@Test func aSquadLeftOutSeesTheMemberAsNotCheckedIn() {
    let log = CheckInLog(member: tracy, checkIns: [checkIn("trained", on: "2026-10-19", to: [runners, lifters])])
    #expect(log.seen(by: lifters).training(on: day("2026-10-19")) == .trained)
    #expect(log.seen(by: swimmers).training(on: day("2026-10-19")) == .notCheckedIn)
    // The member's own counts don't depend on which squads they picked.
    #expect(log.lifetimeTrainedDays == 1)
}

// MARK: - Posting

@Test func anyNumberOfCheckInsADayCanBePosted() throws {
    let log = CheckInLog(member: tracy, checkIns: [
        checkIn("trained", on: "2026-10-19"), checkIn("healthy", on: "2026-10-19"), checkIn("cheat", on: "2026-10-19"),
    ])
    for kind in ["trained", "healthy", "cheat"] {
        try log.checkPost(checkIn(kind, on: "2026-10-19"), today: day("2026-10-19"), memberSquads: [runners])
    }
}

@Test func disclaimerAfterTrainingIsRefused() {
    let log = CheckInLog(member: tracy, checkIns: [checkIn("trained", on: "2026-10-19")])
    #expect(throws: CheckInError.alreadyTrained) {
        try log.checkPost(checkIn("disclaimer", on: "2026-10-19"), today: day("2026-10-19"), memberSquads: [runners])
    }
}

@Test func disclaimersHaveNoLimit() throws {
    let log = CheckInLog(member: tracy, checkIns: [
        checkIn("disclaimer", on: "2026-10-19"), checkIn("disclaimer", on: "2026-10-20"),
        checkIn("disclaimer", on: "2026-10-21"), checkIn("disclaimer", on: "2026-10-22"),
    ])
    try log.checkPost(checkIn("disclaimer", on: "2026-10-22"), today: day("2026-10-22"), memberSquads: [runners])
    try log.checkPost(checkIn("trained", on: "2026-10-22"), today: day("2026-10-22"), memberSquads: [runners])
}

@Test func onlyTodayCanBePosted() {
    let log = CheckInLog(member: tracy, checkIns: [])
    #expect(throws: CheckInError.notToday(day("2026-10-18"))) {
        try log.checkPost(checkIn("trained", on: "2026-10-18"), today: day("2026-10-19"), memberSquads: [runners])
    }
    #expect(throws: CheckInError.notToday(day("2026-10-20"))) {
        try log.checkPost(checkIn("trained", on: "2026-10-20"), today: day("2026-10-19"), memberSquads: [runners])
    }
}

@Test func checkInsGoOnlyToTheMembersSquads() {
    let log = CheckInLog(member: tracy, checkIns: [])
    #expect(throws: CheckInError.notInSquad(swimmers)) {
        try log.checkPost(checkIn("trained", on: "2026-10-19", to: [runners, swimmers]), today: day("2026-10-19"), memberSquads: [runners, lifters])
    }
}

@Test func cantPostForSomeoneElse() {
    let log = CheckInLog(member: tracy, checkIns: [])
    #expect(throws: CheckInError.otherMember(coco)) {
        try log.checkPost(checkIn("trained", on: "2026-10-19", by: coco), today: day("2026-10-19"), memberSquads: [runners])
    }
}

// MARK: - Deleting

@Test func ownCheckInCanBeDeletedTheSameDay() throws {
    let workout = checkIn("trained", on: "2026-10-19")
    let log = CheckInLog(member: tracy, checkIns: [workout])
    try log.checkDelete(workout.id, by: tracy, today: day("2026-10-19"))
    #expect(throws: CheckInError.notToday(day("2026-10-19"))) {
        try log.checkDelete(workout.id, by: tracy, today: day("2026-10-20"))
    }
    #expect(throws: CheckInError.otherMember(coco)) {
        try log.checkDelete(workout.id, by: coco, today: day("2026-10-19"))
    }
    let missing = checkIn("trained", on: "2026-10-19").id
    #expect(throws: CheckInError.notFound(missing)) {
        try log.checkDelete(missing, by: tracy, today: day("2026-10-19"))
    }
}

@Test func deletingTheWorkoutBringsBackTheDisclaimer() {
    let excuse = checkIn("disclaimer", on: "2026-10-19")
    let workout = checkIn("trained", on: "2026-10-19")
    let after = CheckInLog(member: tracy, checkIns: [excuse, workout].filter { $0.id != workout.id })
    #expect(after.training(on: day("2026-10-19")) == .disclaimer)
}

// MARK: - Weekly and lifetime counts

private func plan(startingOn start: String, _ days: [PlanDay], for member: MemberID = tracy) -> WeeklyPlan {
    try! WeeklyPlan(member: member, weekStart: day(start), days: days)
}

@Test func weekCountsTrainedDaysAgainstThePlan() throws {
    // Week starts Monday 2026-10-19; plan: 5 training days, rest Wed and Sun.
    let weekPlan = plan(startingOn: "2026-10-19", [
        .train(.run), .train(.strength), .rest, .train(nil), .train(.yoga), .train(.swim), .rest,
    ])
    let log = CheckInLog(member: tracy, checkIns: [
        checkIn("trained", on: "2026-10-19"), checkIn("trained", on: "2026-10-19"),
        checkIn("disclaimer", on: "2026-10-20"),
        checkIn("trained", on: "2026-10-21"), // a planned rest day, trained anyway
        checkIn("disclaimer", on: "2026-10-22"), checkIn("trained", on: "2026-10-22"),
        checkIn("healthy", on: "2026-10-19"), checkIn("healthy", on: "2026-10-19"),
        checkIn("cheat", on: "2026-10-20"), checkIn("healthy", on: "2026-10-23"),
        checkIn("trained", on: "2026-10-18"), // the week before
        checkIn("trained", on: "2026-10-26"), // the week after
    ])
    let summary = try log.summary(for: weekPlan)
    #expect(summary.trainedDays == 3)
    #expect(summary.plannedTrainingDays == 5)
    #expect(summary.healthyMealDays == 2)
    #expect(summary.days.map(\.training) == [.trained, .disclaimer, .trained, .trained, .notCheckedIn, .notCheckedIn, .notCheckedIn])
    #expect(summary.days.map(\.plan) == weekPlan.days)
    #expect(log.lifetimeTrainedDays == 5)
}

@Test func trainingMoreThanPlannedIsCounted() throws {
    let restWeek = plan(startingOn: "2026-10-19", [.train(.run), .rest, .rest, .rest, .rest, .rest, .rest])
    let log = CheckInLog(member: tracy, checkIns: [checkIn("trained", on: "2026-10-19"), checkIn("trained", on: "2026-10-20")])
    let summary = try log.summary(for: restWeek)
    #expect(summary.trainedDays == 2)
    #expect(summary.plannedTrainingDays == 1)
}

@Test func weekWithoutAPlanStillCounts() throws {
    let week = try Week.containing(day("2026-10-21"), weekStartsOn: .sunday)
    let log = CheckInLog(member: tracy, checkIns: [checkIn("trained", on: "2026-10-18"), checkIn("healthy", on: "2026-10-24")])
    let summary = log.summary(of: week)
    #expect(summary.trainedDays == 1)
    #expect(summary.plannedTrainingDays == nil)
    #expect(summary.healthyMealDays == 1)
    #expect(summary.days.allSatisfy { $0.plan == nil })
}

@Test func everyWeekStartsFresh() throws {
    let log = CheckInLog(member: tracy, checkIns: [checkIn("trained", on: "2026-10-19"), checkIn("trained", on: "2026-10-20")])
    let next = log.summary(of: try Week(startingOn: day("2026-10-26")))
    #expect(next.trainedDays == 0)
    #expect(log.lifetimeTrainedDays == 2)
}

@Test func anotherMembersPlanIsRefused() {
    let log = CheckInLog(member: tracy, checkIns: [])
    #expect(throws: CheckInError.otherMember(coco)) {
        try log.summary(for: plan(startingOn: "2026-10-19", Array(repeating: .rest, count: 7), for: coco))
    }
}
