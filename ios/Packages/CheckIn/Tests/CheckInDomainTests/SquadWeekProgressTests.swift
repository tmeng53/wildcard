import Testing

@testable import CheckInDomain

@Test func daysBeyondThePlanCountButTheBarStopsAtFull() {
    let progress = SquadWeekProgress(done: 25, goal: 22)
    #expect(progress.done == 25)
    #expect(progress.fraction == 1)
    #expect(SquadWeekProgress(done: 3, goal: 10).fraction == 0.3)
    #expect(SquadWeekProgress(done: 3, goal: 0).fraction == 0)
}
