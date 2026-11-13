import CheckInDomain
import Testing

@Test func theDotSwellsAndTheHaloRingsOutAtEachPulsesStart() {
    let start = NewsDotPulse.at(0)
    #expect(start == NewsDotPulse(dotScale: 1, haloScale: 1, haloOpacity: 0.45))
    let swollen = NewsDotPulse.at(NewsDotPulse.period * 0.175)
    #expect(abs(swollen.dotScale - 1.25) < 0.0001)
    #expect(swollen.haloScale > 1 && swollen.haloOpacity < 0.45)
}

@Test func theHaloIsGoneAndTheDotRestsBeforeTheNextPulse() {
    let rest = NewsDotPulse.at(NewsDotPulse.period * 0.9)
    #expect(rest == NewsDotPulse(dotScale: 1, haloScale: 1, haloOpacity: 0))
}

@Test func thePulseRepeatsEveryPeriodAndFitsTwiceInAWhistle() {
    #expect(NewsDotPulse.period == 1.5)
    let first = NewsDotPulse.at(0.3)
    let eighth = NewsDotPulse.at(0.3 + NewsDotPulse.period * 7)
    #expect(abs(first.dotScale - eighth.dotScale) < 0.0001)
    #expect(abs(first.haloScale - eighth.haloScale) < 0.0001)
    #expect(abs(first.haloOpacity - eighth.haloOpacity) < 0.0001)
}
