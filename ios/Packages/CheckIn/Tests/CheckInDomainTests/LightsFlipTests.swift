import CheckInDomain
import Contracts
import Foundation
import Testing

/// 开灯's timeline, as the approved prototype (2026-10-24) computes it.
struct LightsFlipTests {
    private let lit = LightsFlip(isOn: true, reduceMotion: false)
    private let dark = LightsFlip(isOn: false, reduceMotion: false)

    private func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-9 }

    /// The dark holds for the click, drops to half at 0.2 s and fades out from 0.42 s, ease-out,
    /// over 0.3 s; switching off brings it back over 0.3 s.
    @Test func theDarkLiftsInTwoSteps() {
        #expect(lit.darkness(at: 0.1) == 1)
        #expect(near(lit.darkness(at: 0.26), 0.75))
        #expect(lit.darkness(at: 0.4) == 0.5)
        #expect(near(lit.darkness(at: 0.57), 0.125))
        #expect(lit.darkness(at: 0.8) == 0)
        #expect(dark.darkness(at: 0) == 0 && near(dark.darkness(at: 0.15), 0.5) && dark.darkness(at: 0.3) == 1)
    }

    /// The tubes flicker on, off, on, then fade into the day art; a faint flash at each bank.
    @Test func theLampsFlickerOn() {
        #expect([0.03, 0.08, 0.14, 0.2].map(lit.lamps(at:)) == [0, 1, 0.15, 1])
        #expect(near(lit.lamps(at: 0.42), 0.5) && lit.lamps(at: 0.7) == 0)
        #expect(near(lit.flash(at: 0.2), 0.1) && near(lit.flash(at: 0.48), 0.05) && lit.flash(at: 0.35) == 0)
        #expect(dark.lamps(at: 0.08) == 0 && dark.flash(at: 0.2) == 0)
    }

    /// Sleepers wake 0.1 s apart from 0.45 s, their "z z" gone in 0.15 s, their 请假条 back once
    /// they stand; the first one's line from 1.7 s.
    @Test func theSquadWakesOneAfterAnother() {
        #expect([0, 1, 2].map(lit.start(ofSleeper:)) == [0.45, 0.55, 0.65])
        #expect(lit.sleep(ofSleeper: 1, at: 0.5, dozeDuration: 3.4) == 1)
        #expect(lit.sleep(ofSleeper: 1, at: 0.75, dozeDuration: 3.4) == 0)
        #expect(lit.sign(ofSleeper: 0, at: 2.9) == 0 && near(lit.sign(ofSleeper: 0, at: 3.05), 0.5))
        #expect(!lit.showsLine(at: 1.6, hold: 1.6) && lit.showsLine(at: 1.7, hold: 1.6))
        #expect(!lit.showsLine(at: 3.3, hold: 1.6))
    }

    /// Switching off, everyone dozes off together and the "z z" come back after the doze.
    @Test func switchingOffDozesEveryoneOff() {
        #expect(dark.start(ofSleeper: 3) == 0)
        #expect(dark.sleep(ofSleeper: 0, at: 3.4, dozeDuration: 3.4) == 0)
        #expect(dark.sleep(ofSleeper: 0, at: 3.7, dozeDuration: 3.4) == 1)
        #expect(dark.sign(ofSleeper: 0, at: 0) == 1 && dark.sign(ofSleeper: 0, at: 0.2) == 0)
        #expect(!dark.showsLine(at: 2, hold: 1.6))
    }

    /// Reduce Motion: a 0.2 s crossfade, no flicker, flash or line, and poses swap at once.
    @Test func reduceMotionCrossfades() {
        let calm = LightsFlip(isOn: true, reduceMotion: true)
        #expect(near(calm.darkness(at: 0.1), 0.5) && calm.darkness(at: 0.2) == 0)
        #expect(calm.lamps(at: 0.08) == 0 && calm.flash(at: 0.2) == 0)
        #expect(calm.start(ofSleeper: 2) == 0 && calm.sign(ofSleeper: 2, at: 0) == 1)
        #expect(!calm.showsLine(at: 2, hold: 1.6))
    }

    /// The night runs 23:00 to 6:00 and is named by the day it began, so the lights stay on past
    /// midnight and the next night starts dark.
    @Test func aNightIsNamedByTheDayItBegan() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(
                calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
        }
        let night = try LocalDay(year: 2026, month: 10, day: 23)
        #expect(LightsFlip.night(at: try at(23, 23, 30), in: zone) == night)
        #expect(LightsFlip.night(at: try at(24, 5, 59), in: zone) == night)
        #expect(LightsFlip.night(at: try at(24, 6), in: zone) == nil)
        #expect(LightsFlip.night(at: try at(23, 22, 59), in: zone) == nil)
        #expect(LightsFlip.night(at: try at(24, 23), in: zone) == (try LocalDay(year: 2026, month: 10, day: 24)))
    }
}
