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
        #expect(script.cheers == [2.2 + 0.3 + 0.3, 2.2 + 0.3 + 0.15, 2.2 + 0.3])
        #expect(abs(script.myLine - 2.4) < 1e-9)
    }

    @Test func itEndsWhenTheLastLineHasBeenUpItsTime() {
        let script = EntranceScript(spot: spot, teammates: [.init(feet: Point(x: 35, y: 626), height: 72)])
        #expect(abs(script.end - (2.5 + 4.2)) < 1e-9)
        #expect(abs(EntranceScript(spot: spot, teammates: []).end - (2.4 + 4.2)) < 1e-9)
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

struct EntranceMotionTests {

    private let entrance: Clip

    init() throws {
        entrance = try PlaceholderCharacter.entrance()
    }

    private func rootY(at time: Double) -> Double {
        entrance.tracks.first { $0.part == "root" && $0.channel == .y }?.value(at: time) ?? 0
    }

    @Test func theScriptsTakeoffAndLandingAreTheClipsOwn() {
        // Up is negative, in canvas points; the jump goes over 300 high.
        #expect(abs(rootY(at: EntranceScript.takeoffInClip - 0.05)) < 1)
        #expect(rootY(at: EntranceScript.takeoffInClip + 0.2) < -100)
        #expect(rootY(at: EntranceScript.landingInClip - 0.05) < -10)
        #expect(abs(rootY(at: EntranceScript.landingInClip)) < 1)
    }

    @Test func theNewMemberRunsInFromTheRightAndStopsOnTheSpot() {
        let motion = EntranceMotion(spot: Point(x: 195, y: 676), scale: 0.34, entrance: entrance)
        #expect(motion.newcomerX(at: 0) > 390)
        #expect(abs(motion.newcomerX(at: EntranceScript.land) - 195) < 0.5)
        #expect(motion.newcomerX(at: 5) == 195)
    }

    @Test func theyTurnOneAndAHalfTimesInTheAir() {
        #expect(EntranceMotion.facing(at: 1) == -1)
        #expect(EntranceMotion.facing(at: EntranceScript.land) == 1)
        let air = EntranceScript.takeoffInClip..<EntranceScript.landingInClip
        let samples = stride(from: air.lowerBound, to: air.upperBound, by: 0.005).map(EntranceMotion.facing(at:))
        let flips = zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        #expect(flips == 3)
    }

    @Test func theShockwaveAndRingFollowTheLanding() {
        #expect(EntranceMotion.shockwave(at: EntranceScript.land - 0.01) == nil)
        #expect(EntranceMotion.shockwave(at: EntranceScript.land)?.radius == 30)
        #expect(EntranceMotion.shockwave(at: EntranceScript.land + 0.6) == nil)
        #expect(EntranceMotion.ring(at: EntranceScript.land - 0.01) == (0, 0))
        #expect(EntranceMotion.ring(at: EntranceScript.land + 0.5) == (1, 1))
    }

    @Test func theDustIsKickedUpRunningSkiddingAndLanding() {
        let motion = EntranceMotion(spot: Point(x: 195, y: 676), scale: 0.34, entrance: entrance)
        #expect(motion.puffs.count == 14)
        #expect(motion.puffs.filter { $0.start == EntranceScript.land }.count == 4)
    }

    @Test func aWatchingTeammateEndsFacingFront() throws {
        let motion = EntranceMotion(spot: Point(x: 195, y: 676), scale: 0.34, entrance: entrance)
        let clip = try motion.watching(from: Point(x: 60, y: 600), until: 2.5, bounces: true)
        #expect(clip.duration == 2.25)
        for track in clip.tracks {
            #expect(abs(track.value(at: 0)) < 1e-9)
            #expect(abs(track.value(at: clip.duration)) < 1e-9)
        }
        let head = clip.tracks.first { $0.part == "head" }
        // Mid-run, the runner is to the teammate's right, so the head turns that way.
        #expect((head?.value(at: 0.8) ?? 0) > 0)
        let mirrored = try motion.watching(from: Point(x: 60, y: 600), facing: -1, until: 2.5, bounces: false)
        #expect((mirrored.tracks.first { $0.part == "head" }?.value(at: 0.8) ?? 0) < 0)
        #expect(mirrored.tracks.count == 2)
    }
}
