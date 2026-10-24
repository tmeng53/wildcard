import Testing

@testable import DesignSystem

struct RulerScaleTests {
    private let minutes = RulerScale(range: 5...300, step: 5, midEvery: 15, labelEvery: 30)

    @Test func valuesRunEveryStepFromEndToEnd() {
        #expect(minutes.values.count == 60)
        #expect(minutes.values.prefix(3) == [5, 10, 15])
        #expect(minutes.values.last == 300)
    }

    @Test func indexesPastEitherEndStopAtTheEnd() {
        #expect(minutes.value(atIndex: 0) == 5)
        #expect(minutes.value(atIndex: 11) == 60)
        #expect(minutes.value(atIndex: -3) == 5)
        #expect(minutes.value(atIndex: 99) == 300)
    }

    @Test func valuesSnapToTheNearestStep() {
        #expect(minutes.snapped(62) == 60)
        #expect(minutes.snapped(63) == 65)
        #expect(minutes.snapped(1) == 5)
        #expect(minutes.snapped(600) == 300)
        #expect(minutes.index(of: 75) == 14)
    }

    @Test func movingStepsHoldsToTheRange() {
        #expect(minutes.value(60, movedBy: 1) == 65)
        #expect(minutes.value(60, movedBy: -2) == 50)
        #expect(minutes.value(5, movedBy: -1) == 5)
        #expect(minutes.value(300, movedBy: 1) == 300)
    }

    @Test func longMarksFallOnRoundNumbers() {
        #expect(minutes.mark(for: 30) == .major)
        #expect(minutes.mark(for: 45) == .mid)
        #expect(minutes.mark(for: 50) == .minor)
        #expect(minutes.mark(for: 90) == .major)
    }
}

struct EveryMinuteRulerTests {
    private let minutes = RulerScale(range: 1...360, step: 1, midEvery: 5, labelEvery: 15)

    @Test func everyMinuteFromOneToSixHours() {
        #expect(minutes.values.count == 360)
        #expect(minutes.index(of: 60) == 59)
        #expect(minutes.value(atIndex: 59) == 60)
        #expect(minutes.snapped(0) == 1)
        #expect(minutes.snapped(600) == 360)
    }

    @Test func marksCountFromZeroNotTheStart() {
        #expect(minutes.mark(for: 15) == .major)
        #expect(minutes.mark(for: 10) == .mid)
        #expect(minutes.mark(for: 1) == .minor)
    }
}
