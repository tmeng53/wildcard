import Contracts
import Testing

@testable import CheckInDomain

private let week = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"]

private func fiveDayPlan(for member: MemberID) throws -> WeeklyPlan {
    let train = PlanDay.train(.sport(.run))
    return try WeeklyPlan(
        member: member, weekStart: try LocalDay(week[0]), days: [train, train, train, train, train, .rest, .rest])
}

@Test func squadProgressSumsTrainedDaysAgainstEveryonesPlan() throws {
    // Tracy trains twice on Monday and once Tuesday, and takes a 请假 on Wednesday:
    // two days. Coco trains Monday: one day.
    let tracyLog = CheckInLog(
        member: tracy,
        checkIns: [
            checkIn("trained", on: week[0]), checkIn("trained", on: week[0]), checkIn("trained", on: week[1]),
            checkIn("disclaimer", on: week[2]), checkIn("healthy", on: week[2]),
        ])
    let cocoLog = CheckInLog(member: coco, checkIns: [checkIn("trained", on: week[0], by: coco)])
    let progress = SquadWeekProgress(members: [
        try tracyLog.summary(for: fiveDayPlan(for: tracy)), try cocoLog.summary(for: fiveDayPlan(for: coco)),
    ])
    #expect(progress == SquadWeekProgress(done: 3, goal: 10))
    #expect(progress.fraction == 0.3)
}

@Test func daysBeyondThePlanCountButTheBarStopsAtFull() {
    let progress = SquadWeekProgress(done: 25, goal: 22)
    #expect(progress.done == 25)
    #expect(progress.fraction == 1)
    #expect(SquadWeekProgress(done: 3, goal: 0).fraction == 0)
    #expect(SquadWeekProgress(done: 14, goal: 22).addingTrainedDay() == SquadWeekProgress(done: 15, goal: 22))
}

@Test func aMemberWithoutAPlanAddsDaysButNoGoal() throws {
    let log = CheckInLog(member: coco, checkIns: [checkIn("trained", on: week[3], by: coco)])
    let unplanned = log.summary(of: try Week(startingOn: try LocalDay(week[0])))
    #expect(SquadWeekProgress(members: [unplanned]) == SquadWeekProgress(done: 1, goal: 0))
}

@Test func aDisclaimerIsOnlyOfferedBeforeTrainingAndOnceADay() {
    #expect(TrainingStatus.notCheckedIn.allowsDisclaimer)
    #expect(!TrainingStatus.trained.allowsDisclaimer)
    #expect(!TrainingStatus.disclaimer.allowsDisclaimer)
}
