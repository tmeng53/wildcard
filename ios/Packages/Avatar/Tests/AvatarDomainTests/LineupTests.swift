import AvatarDomain
import Testing

// Expected values come from the approved prototype's own formula (2026-10-22), run in Node.

@Test func fiveStandInARowCenteredOnTheStrip() {
    let row = Lineup(count: 5, width: 390)
    #expect(!row.walks)
    #expect(row.spots(at: 0).map(\.left) == [15, 87, 159, 231, 303])
    // Standing still: the time changes nothing, and nobody hops.
    #expect(row.spots(at: 12.5) == row.spots(at: 0))
    #expect(row.spots(at: 12.5).allSatisfy { $0.lift == 0 })
}

@Test func fewerThanFiveStayCentered() {
    #expect(Lineup(count: 2, width: 390).spots(at: 0).map(\.left) == [123, 195])
    #expect(Lineup(count: 1, width: 390).spots(at: 0).map(\.left) == [159])
    #expect(Lineup(count: 0, width: 390).spots(at: 0).isEmpty)
}

@Test func sixOrMoreWalkThroughInALoopingQueue() {
    let queue = Lineup(count: 8, width: 390)
    #expect(queue.walks)
    #expect(queue.spots(at: 1.3).map(\.left) == [507, -39, 39, 117, 195, 273, 351, 429])
    let lifts = queue.spots(at: 1.3).map { ($0.lift * 10_000).rounded() / 10_000 }
    #expect(lifts == [1.8406, 0.1257, 1.6047, 3.1385, 4.2876, 4.9114, 4.9334, 4.3509])
    // One whole loop (8 × 78 at 30 a second) later everyone is back where they were.
    let later = queue.spots(at: 1.3 + 8 * 78 / 30).map(\.left)
    #expect(zip(later, queue.spots(at: 1.3).map(\.left)).allSatisfy { abs($0 - $1) < 1e-9 })
}

@Test func aBiggerStripScalesEveryLength() {
    let big = Lineup(count: 8, width: 390).scaled(by: 2)
    #expect(big.figureWidth == 144)
    #expect(big.spots(at: 1.3)[1].left == -78)
    // The first walker's hop peaks 1/4.8 s in: twice the design's 5.
    #expect(abs(big.spots(at: 1 / 4.8)[0].lift - 10) < 1e-9)
}

@Test func onAWidePhoneSixWalkersComeBackInPastTheEdge() {
    let queue = Lineup(count: 6, width: 440)
    // The loop is the strip and one walker long, so nobody appears inside the right edge.
    #expect(queue.spots(at: 0).map(\.left) == [-78, 0, 78, 156, 234, 312])
    // The first walker, just off the left edge at 0, comes back in from 440 a moment later.
    #expect(abs(queue.spots(at: 0.1)[0].left - 437) < 1e-9)
    #expect(queue.spots(at: 3).map(\.left) == [350, 428, -12, 66, 144, 222])
}

@Test func standingStillTheQueueShowsTheWalkersWhoFit() {
    #expect(Lineup(count: 8, width: 390).rest.map(\.left) == [3, 81, 159, 237, 315, 393, 471, 549])
    #expect(Lineup(count: 8, width: 390).rest.allSatisfy { $0.lift == 0 })
    #expect(Lineup(count: 5, width: 390).rest.map(\.left) == [15, 87, 159, 231, 303])
}
