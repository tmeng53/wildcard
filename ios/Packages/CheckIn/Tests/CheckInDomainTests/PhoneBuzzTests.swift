import CheckInDomain
import Testing

@Test func theCoachHopsAndSwaysOnceEachBuzz() {
    // Still before the buzz, then up at its height, then down again.
    #expect(PhoneBuzz.hop(at: 0) == 0)
    #expect(abs(PhoneBuzz.hop(at: 0.36) - 15) < 0.001)
    #expect(PhoneBuzz.hop(at: 0.6) == 0)
    // It sways left, right and left, then stands straight.
    #expect(abs(PhoneBuzz.sway(at: 0.48) + 2) < 0.001)
    #expect(abs(PhoneBuzz.sway(at: 0.6) - 2) < 0.001)
    #expect(PhoneBuzz.sway(at: 1.5) == 0)
    // The lines show for the buzz only, and the next period starts over.
    #expect(PhoneBuzz.lines(at: 0.6) == 1)
    #expect(PhoneBuzz.lines(at: 2) == 0)
    #expect(abs(PhoneBuzz.hop(at: 3.36) - 15) < 0.001)
}
