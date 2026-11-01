import Testing

@testable import CheckInDomain

@Test func theSquadDropsOneAfterAnotherWithMeLast() {
    let five = DropIn(count: 5)
    #expect(five.start(of: 0) == 0.15)
    #expect(abs(five.start(of: 4) - 0.71) < 1e-9)
    let eight = DropIn(count: 8)
    #expect(abs(eight.start(of: 7) - 0.7625) < 1e-9)
}

@Test func aFallingFigureStartsAboveTheScreenAndStopsLiftingOnLanding() {
    // A spot at 600 whose clip lifts it 147 points starts 513 points higher still.
    #expect(DropIn.lift(at: 0, spotY: 600, clipLift: 147) == 513)
    #expect(DropIn.lift(at: 0.55, spotY: 600, clipLift: 147) == 0)
    #expect(DropIn.lift(at: 1, spotY: 600, clipLift: 147) == 0)
    // Near the top, the clip's own lift is enough.
    #expect(DropIn.lift(at: 0, spotY: 50, clipLift: 147) == 0)
}

@Test func theCardThenTheButtonThenTheTabBarComeIn() {
    let drop = DropIn(count: 1)
    #expect(abs(drop.cardOffset(at: 1.35) - (-260)) < 1e-9)
    #expect(drop.cardOffset(at: 1.85) == 0)
    #expect(abs(drop.buttonOffset(at: 1.8) - (160)) < 1e-9)
    #expect(drop.buttonOffset(at: 2.2) == 0)
    #expect(DropIn.tabBarReturns == 1.9)
    #expect(abs(drop.finished - 2.3) < 1e-9)
    #expect(abs(DropIn(count: 8).finished - 2.6625) < 1e-9)
}
