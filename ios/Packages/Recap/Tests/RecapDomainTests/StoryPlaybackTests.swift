import Contracts
import Foundation
import Testing

@testable import RecapDomain

@Test func pagesPlayOneAfterAnotherAndTheLastOneStays() {
    var playback = StoryPlayback(durations: [5, 4, 3], startingAt: 100)
    #expect(playback.segments(at: 102.5) == [0.5, 0, 0])
    let moved1 = playback.advance(to: 104.9)

    #expect(moved1 == false)
    let moved2 = playback.advance(to: 105)

    #expect(moved2)
    #expect(playback.index == 1)
    let moved3 = playback.advance(to: 120)

    #expect(moved3)
    #expect(playback.index == 2)
    #expect(playback.isLast)
    #expect(playback.segments(at: 200) == [1, 1, 1])
    let moved4 = playback.advance(to: 300)

    #expect(moved4 == false)
}

@Test func aLongGapSkipsEveryPageWhoseTimeRan() {
    var playback = StoryPlayback(durations: [5, 4, 3, 2], startingAt: 0)
    playback.advance(to: 10)
    #expect(playback.index == 2)
    #expect(playback.elapsed(at: 10) == 1)
}

@Test func tapsGoOnAndBackAndTheEndIsTheReadersToClose() {
    var playback = StoryPlayback(durations: [5, 4, 3], startingAt: 0)
    playback.previous(at: 2)
    #expect(playback.index == 0)
    #expect(playback.elapsed(at: 3) == 1)
    let moved5 = playback.next(at: 3)

    #expect(moved5)
    #expect(playback.index == 1)
    #expect(playback.elapsed(at: 3) == 0)
    let moved6 = playback.next(at: 4)

    #expect(moved6)
    let moved7 = playback.next(at: 5)

    #expect(moved7 == false)
    playback.previous(at: 6)
    #expect(playback.index == 1)
}

@Test func holdingPausesThePageAndItsSegment() {
    var playback = StoryPlayback(durations: [5, 4], startingAt: 0)
    playback.pause(at: 2)
    #expect(playback.isPaused)
    let moved8 = playback.advance(to: 30)

    #expect(moved8 == false)
    #expect(playback.segments(at: 30) == [0.4, 0])
    playback.resume(at: 30)
    #expect(playback.elapsed(at: 31) == 3)
    let moved9 = playback.advance(to: 33)

    #expect(moved9)
    #expect(playback.index == 1)
}

@Test func theWeekHopsDayByDay() throws {
    func day(_ number: Int) throws -> LocalDay { try LocalDay(year: 2026, month: 10, day: number) }
    let beats = MyWeekBeats(days: [
        .init(day: try day(13), kind: .trained(.run)),
        .init(day: try day(14), kind: .rest),
        .init(day: try day(15), kind: .none),
        .init(day: try day(16), kind: .disclaimer),
    ])
    // Tenths of a second; the sums carry floating-point dust.
    let tenths = { (time: Double) in (time * 10).rounded() / 10 }
    #expect(beats.beats.map { tenths($0.land) } == [0.2, 1.6, 2.9, 3.6])
    #expect(beats.beats.map(\.clip) == [.sport(.runWalk), .award(.doze), nil, .award(.flat)])
    #expect(tenths(beats.end) == 4.6)
    #expect(beats.beat(at: 0.1) == nil)
    #expect(beats.beat(at: 1.7)?.day == 1)
    let empty = MyWeek(plan: 5, days: [], healthyMeals: 0, cheatMeals: 0, reactionsReceived: 0)
    #expect(StoryPage.myWeek(empty).duration == 1.5)
}
