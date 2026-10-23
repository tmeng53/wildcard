import OnboardingDomain
import Testing

/// WILDCARD on a 390-point screen, as the open screen lays it out.
private let layout = FinishLineSprint.Layout(wordRight: 316, capTop: 110, baseline: 153, floorTop: 557)

struct FinishLineSprintTests {
    @Test func theWordStartsOffScreenAndLeaningIn() {
        let sprint = FinishLineSprint(layout: layout)
        #expect(sprint.offset == -340)
        #expect(sprint.lean == -14)
        #expect(sprint.brokeAt == nil)
        #expect(sprint.tapePieces.count == 1)
        #expect(sprint.tapeOpacity == 1)
    }

    @Test func theTapeBreaksOnceInTwoAsTheWordArrives() {
        var sprint = FinishLineSprint(layout: layout)
        let (breakTime, end) = FinishLineSprint.timing(for: layout)
        #expect(breakTime > 0.25 && breakTime < 0.32, "\(breakTime)")
        #expect(end > breakTime + 0.75 && end < 2.5, "\(end)")
        sprint.advance(to: breakTime - FinishLineSprint.step)
        #expect(sprint.brokeAt == nil)
        sprint.advance(to: breakTime)
        #expect(sprint.brokeAt == breakTime)
        #expect(sprint.tapePieces.count == 2)
        sprint.advance(to: breakTime + 0.5)
        #expect(sprint.brokeAt == breakTime)
        #expect(sprint.tapePieces.count == 2)
    }

    @Test func theWordSettlesUprightAtItsPlaceAndTheTapeIsGone() {
        var sprint = FinishLineSprint(layout: layout)
        sprint.advance(to: FinishLineSprint.timing(for: layout).ends)
        #expect(sprint.isFinished)
        #expect(abs(sprint.offset) < 0.05)
        #expect(abs(sprint.lean) < 0.05)
        #expect(abs(sprint.lift) < 0.05)
        #expect(sprint.tapeOpacity == 0)
    }

    @Test func theWordNeverRunsPastItsPlaceByMoreThanAHair() {
        var sprint = FinishLineSprint(layout: layout)
        var farthest = -Double.infinity
        while sprint.time < 3 {
            sprint.advance(to: sprint.time + FinishLineSprint.step)
            farthest = max(farthest, sprint.offset)
        }
        #expect(farthest < 1)
    }

    @Test func theBrokenTapeLiesOnTheFloorNotThroughIt() {
        var sprint = FinishLineSprint(layout: layout)
        sprint.advance(to: 2)
        for point in sprint.tapePieces.joined() {
            #expect(point.y <= layout.floorTop)
        }
    }
}
