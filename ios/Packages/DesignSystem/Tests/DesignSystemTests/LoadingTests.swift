import Testing

@testable import DesignSystem

struct LoadingTests {
    /// The approved defaults (loader design, 2026-10-24).
    @Test func waitsUseTheApprovedTimes() {
        #expect(Loading.pageDelay == 0.5 && Loading.inlineDelay == 0.3)
        #expect(Loading.minimumShown == 0.6 && Loading.giveUpAfter == 15)
        #expect(Loading.dotCycle == 0.9 && Loading.dotStagger == 0.12 && Loading.dotRise == 5)
        #expect(Loading.dotsWidth == 26)
    }

    /// A loader that showed briefly stays for the rest of 0.6 s; one shown longer goes at once.
    @Test func aShownLoaderStaysLongEnough() {
        #expect(abs(Loading.hold(afterShowing: 0.2) - 0.4) < 1e-9)
        #expect(Loading.hold(afterShowing: 0.6) == 0)
        #expect(Loading.hold(afterShowing: 3) == 0)
    }

    /// Each dot is up at a quarter of its cycle, back down by 60% and still after, one after another.
    @Test func dotsHopInTurn() {
        func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-9 }
        #expect(near(Loading.hop(dot: 0, at: 0), 0))
        #expect(near(Loading.hop(dot: 0, at: 0.225), 1))
        #expect(near(Loading.hop(dot: 0, at: 0.54), 0))
        #expect(near(Loading.hop(dot: 0, at: 0.8), 0))
        #expect(near(Loading.hop(dot: 1, at: 0.345), 1))
        #expect(near(Loading.hop(dot: 2, at: 0.465), 1))
        // The next cycle repeats the first, and a dot before its first hop is at rest.
        #expect(near(Loading.hop(dot: 0, at: 0.9 + 0.225), 1))
        #expect(near(Loading.hop(dot: 2, at: 0.1), 0))
        #expect(near(Loading.dotOpacity(dot: 0, at: 0), 0.35) && near(Loading.dotOpacity(dot: 0, at: 0.225), 1))
    }
}
