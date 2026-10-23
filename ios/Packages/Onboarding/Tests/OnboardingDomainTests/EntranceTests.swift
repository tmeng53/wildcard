import AvatarArt
import AvatarDomain
import OnboardingDomain
import Testing

/// The same numbers every run, so a test can say exactly which lines come out.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

struct WelcomeLinesTests {
    @Test func everyoneGetsALineFromTheirOwnPool() {
        var generator = SeededGenerator(state: 7)
        let lines = WelcomeLines.pick(
            for: [.newcomer, .teammate(.drama), .teammate(.shy), .teammate(.deadpan)], using: &generator)
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("welcome.me."))
        #expect(lines[1].hasPrefix("welcome.drama."))
        #expect(lines[2].hasPrefix("welcome.shy."))
        #expect(lines[3].hasPrefix("welcome.deadpan."))
    }

    @Test func teammatesWithOnePersonaNeverRepeatInOneEntrance() {
        var generator = SeededGenerator(state: 42)
        let lines = WelcomeLines.pick(
            for: Array(repeating: .teammate(.energetic), count: WelcomeLines.perPersona), using: &generator)
        #expect(Set(lines).count == WelcomeLines.perPersona)
    }

    @Test func aPoolThatRunsOutComesRoundAgain() {
        var generator = SeededGenerator(state: 1)
        let lines = WelcomeLines.pick(
            for: Array(repeating: .teammate(.showoff), count: WelcomeLines.perPersona + 1), using: &generator)
        #expect(lines.count == WelcomeLines.perPersona + 1)
        #expect(Set(lines.prefix(WelcomeLines.perPersona)).count == WelcomeLines.perPersona)
    }

    @Test func entrancesPickAfresh() {
        var generator = SeededGenerator(state: 3)
        let speakers = Array(repeating: WelcomeLines.Speaker.teammate(.drama), count: 3)
        let first = WelcomeLines.pick(for: speakers, using: &generator)
        let second = WelcomeLines.pick(for: speakers, using: &generator)
        #expect(first != second)
    }

    @Test func thereAreTenLinesAPersonaAndEightOfMine() {
        #expect(WelcomeLines.allKeys.count == Persona.allCases.count * 10 + 8)
        #expect(WelcomeLines.allKeys.contains("welcome.me.8"))
        #expect(WelcomeLines.allKeys.contains("welcome.shy.10"))
    }
}

struct EntranceScriptTests {

    private let spot = Point(x: 195, y: 676)

    @Test func theNearestTeammateCheersFirst() {
        let script = EntranceScript(
            spot: spot,
            teammates: [
                .init(feet: Point(x: 35, y: 626), height: 72),
                .init(feet: Point(x: 155, y: 566), height: 70),
                .init(feet: Point(x: 275, y: 626), height: 72),
            ])
        // Distances: 168, 117, 94.
        #expect(script.cheers == [2.1 + 0.3 + 0.3, 2.1 + 0.3 + 0.15, 2.1 + 0.3])
        #expect(abs(script.myLine - 2.3) < 1e-9)
    }

    @Test func itEndsWhenTheLastLineHasBeenUpItsTime() {
        let script = EntranceScript(spot: spot, teammates: [.init(feet: Point(x: 35, y: 626), height: 72)])
        #expect(script.end == 2.4 + 4.2)
        #expect(EntranceScript(spot: spot, teammates: []).end == 2.3 + 4.2)
    }

    @Test func aBubbleStandsAboveItsSpeaker() {
        let script = EntranceScript(spot: spot, teammates: [.init(feet: Point(x: 60, y: 600), height: 80)])
        let points = script.bubbles(sizes: [(80, 36), (90, 36)], myHeight: 90, width: 390)
        #expect(points[0] == Point(x: 195, y: 586))
        #expect(points[1] == Point(x: 60, y: 520))
    }

    @Test func aBubbleStaysOnScreen() {
        let script = EntranceScript(spot: spot, teammates: [.init(feet: Point(x: 10, y: 600), height: 80)])
        let points = script.bubbles(sizes: [(80, 36), (120, 36)], myHeight: 90, width: 390)
        #expect(points[1].x == 68)
    }

    @Test func aLaterBubbleMovesUpUntilItCoversNone() {
        // Two teammates side by side: the second's bubble would sit on the first's.
        let script = EntranceScript(
            spot: spot,
            teammates: [
                .init(feet: Point(x: 150, y: 600), height: 80),
                .init(feet: Point(x: 200, y: 600), height: 80),
            ])
        let points = script.bubbles(sizes: [(60, 36), (100, 36), (100, 36)], myHeight: 200, width: 390)
        let first = points[1]
        let second = points[2]
        // The nearer teammate (the second) cheers first and keeps its place.
        #expect(second == Point(x: 200, y: 520))
        #expect(first.y <= second.y - 36 - 4)
    }
}
