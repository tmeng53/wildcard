import Testing

@testable import CheckInDomain

@Test func daysBeyondThePlanCountButTheBarStopsAtFull() {
    let progress = SquadWeekProgress(done: 25, goal: 22)
    #expect(progress.done == 25)
    #expect(progress.fraction == 1)
    #expect(SquadWeekProgress(done: 3, goal: 10).fraction == 0.3)
    #expect(SquadWeekProgress(done: 3, goal: 0).fraction == 0)
    #expect(SquadWeekProgress(done: 14, goal: 22).addingTrainedDay() == SquadWeekProgress(done: 15, goal: 22))
}

@Test func aDisclaimerIsOnlyOfferedBeforeTrainingAndOnceADay() {
    #expect(TrainingStatus.notCheckedIn.allowsDisclaimer)
    #expect(!TrainingStatus.trained.allowsDisclaimer)
    #expect(!TrainingStatus.disclaimer.allowsDisclaimer)
}
