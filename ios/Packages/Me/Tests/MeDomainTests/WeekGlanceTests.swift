import Contracts
import MeDomain
import Testing

struct WeekGlanceTests {
    /// A 练了 marks its day whatever the plan said; other days follow the plan, and a training
    /// day gone by without one stays planned, never missed.
    @Test func marksFollowThePlanAndTheTraining() {
        let glance = WeekGlance(
            number: 45,
            plan: [.train(nil), .rest, .train(nil), .train(nil), .train(nil), .rest, .rest],
            trainedDays: [0, 1, 4], today: 3)
        #expect(glance.number == 45)
        #expect(
            glance.days.map(\.mark) == [.trained, .trained, .planned, .planned, .trained, .rest, .rest])
        #expect(glance.days.map(\.isToday) == [false, false, false, true, false, false, false])
    }

    /// Outside the week (a plan read for another week), no day is today.
    @Test func noTodayOutsideTheWeek() {
        let glance = WeekGlance(number: 1, plan: Array(repeating: .rest, count: 7), trainedDays: [], today: nil)
        #expect(glance.days.allSatisfy { !$0.isToday && $0.mark == .rest })
    }
}
