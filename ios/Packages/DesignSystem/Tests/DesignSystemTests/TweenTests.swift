import Testing

@testable import DesignSystem

struct KraftTests {
    /// The carton's colours, from the approved scene-pick prototype (2026-10-22).
    @Test func theCartonIsKraftFromThePrototype() {
        #expect(
            [
                Palette.kraft, Palette.kraftShade, Palette.kraftBandLine, Palette.kraftFlap, Palette.kraftFlapShade,
                Palette.kraftTape, Palette.kraftInk, Palette.dusk,
            ].map(\.hex) == ["#D2AE80", "#C39C6C", "#B88E5E", "#C79E6D", "#BE9563", "#E6CDA4", "#9E7849", "#1A1C22"])
        #expect(TypeRamp.caption.size == 12 && TypeRamp.caption.face == .text(.regular))
    }
}

struct TweenTests {
    /// The prototype's curves at a few points, as its JavaScript computes them.
    @Test func curvesMatchThePrototype() {
        func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-9 }
        #expect(near(Tween.cubicOut(0.5), 0.875) && near(Tween.quadIn(0.5), 0.25))
        #expect(near(Tween.cubicInOut(0.25), 0.0625) && near(Tween.cubicInOut(0.75), 0.9375))
        #expect(near(Tween.backOut(0.5), 1.0875) && near(Tween.backOut(1), 1) && near(Tween.backOut(0), 0))
        #expect(Tween.squash(1) == 0 && near(Tween.squash(0), 1))
        #expect(Tween.progress(1.25, from: 1, lasting: 0.5) == 0.5 && Tween.progress(0, from: 1, lasting: 0.4) == 0)
        #expect(Tween.mix(10, 20, 0.25) == 12.5)
        // CSS ease-in-out, as the prototype's bezier solver gives it.
        #expect(abs(Tween.easeInOut(0.25) - 0.129_161) < 1e-4 && abs(Tween.easeInOut(0.5) - 0.5) < 1e-4)
    }

    /// A picked carton's shake: -7°, 6°, -4°, 2° in the first fifth of 2.4 s, then still.
    @Test func thePickedCartonWiggles() {
        #expect(abs(Wiggle.degrees(at: 0.096) + 7) < 1e-6 && abs(Wiggle.degrees(at: 0.192) - 6) < 1e-6)
        #expect(Wiggle.degrees(at: 0) == 0 && Wiggle.degrees(at: 1.2) == 0)
        #expect(abs(Wiggle.degrees(at: 2.4 + 0.288) + 4) < 1e-6)
    }
}

struct SpeechTimingTests {
    @Test func bubblesHoldThenFade() {
        #expect([Motion.speechHold, Motion.speechFade, Motion.speechStagger] == [1.6, 0.2, 0.06])
        #expect(Motion.noticeHold == 4)
    }
}

struct PullCordTests {
    /// The cord's colours, from the approved 开灯 prototype (2026-10-24).
    @Test func theCordIsThePrototypes() {
        #expect(
            [
                Palette.cordChain, Palette.cordCap, Palette.cordScrew, Palette.bulbLit, Palette.bulbLitLine,
                Palette.bulbFilament,
            ].map(\.hex) == ["#C9CED6", "#9AA2AE", "#B9C0CA", "#FFE9A8", "#F2C14E", "#E0A526"])
        #expect(PullCordMotion.length == 70 && PullCordMotion.maxPull == 36 && PullCordMotion.clickPull == 24)
    }

    /// A drag gives less the further it goes, clicks before 24 points of finger travel run out,
    /// and stops at 36.
    @Test func aDragFollowsWithResistance() {
        #expect(PullCordMotion.pull(dragged: -10) == 0)
        #expect(abs(PullCordMotion.pull(dragged: 10) - 10.91) < 0.01)
        #expect(abs(PullCordMotion.pull(dragged: 30) - 25.44) < 0.01)
        #expect(PullCordMotion.pull(dragged: 26) < PullCordMotion.clickPull)
        #expect(PullCordMotion.pull(dragged: 80) == 36)
    }

    /// A tap pulls 28 points over 0.12 s; a release springs back past rest, swings under 5° and is
    /// still after 2 s; Reduce Motion keeps it from swinging.
    @Test func aReleaseSpringsAndSwings() {
        #expect(PullCordMotion.tap(at: 0) == 0 && PullCordMotion.tap(at: 0.06) == 14 && PullCordMotion.tap(at: 1) == 28)
        #expect(PullCordMotion.release(from: 28, at: 0) == (28, 0))
        let samples = stride(from: 0.0, to: 2, by: 0.01).map { PullCordMotion.release(from: 36, at: $0) }
        #expect(samples.map(\.offset).min() ?? 0 >= -6 && samples.map(\.offset).min() ?? 0 < 0)
        #expect(samples.map { abs($0.degrees) }.max() ?? 9 < 5 && samples.map { abs($0.degrees) }.max() ?? 0 > 3)
        #expect(PullCordMotion.release(from: 28, at: 2) == (0, 0))
        #expect(PullCordMotion.release(from: 28, at: 0.3, swings: false).degrees == 0)
    }
}

struct TicketRockTests {
    /// The approved design A 两张票 (2026-10-31): apart by 30% of the 0.9 s beat, back by 60%,
    /// then still until the next beat.
    @Test func ticketsRockOnTheBeat() {
        func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-6 }
        #expect(near(TicketRock.amount(at: 0), 0))
        #expect(near(TicketRock.amount(at: 0.27), 1))
        #expect(near(TicketRock.amount(at: 0.54), 0))
        #expect(near(TicketRock.amount(at: 0.8), 0))
        #expect(near(TicketRock.amount(at: 0.9 + 0.27), 1))
        // The overshoot past the top, as CSS's cubic-bezier(0.34, 1.56, 0.64, 1) gives it.
        #expect(TicketRock.amount(at: 0.18) > 1)
    }
}

struct LaunchWaveTests {
    private func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 1e-6 }

    /// The approved design A 字母浪 (2026-11-04): the first frame is the system's launch screen,
    /// the logo alone at the centre and every letter hidden below its place.
    @Test func opensOnTheLaunchScreen() {
        #expect(near(LaunchWave.logoLift(at: 0), 0))
        #expect(near(LaunchWave.rock(at: 0), 0))
        for index in 0..<8 {
            #expect(near(LaunchWave.letter(index, at: 0).offset, 22))
            #expect(near(LaunchWave.letter(index, at: 0).opacity, 0))
        }
    }

    /// The logo lifts 30 points in 0.35 s; the last letter lands by 0.73 s, inside the 0.8 s the
    /// cover stays up at least.
    @Test func wordLandsBeforeTheCoverCanFade() {
        #expect(near(LaunchWave.logoLift(at: 0.35), 30))
        #expect(LaunchWave.logoLift(at: 0.2) > 30)
        #expect(near(LaunchWave.letter(0, at: 0.1).opacity, 0))
        #expect(near(LaunchWave.letter(7, at: 0.73).offset, 0))
        #expect(near(LaunchWave.letter(7, at: 0.73).opacity, 1))
        #expect(
            LaunchWave.letterStart + 7 * LaunchWave.letterStagger + LaunchWave.letterDuration <= LaunchWave.entrance)
        #expect(LaunchWave.word.count == 8)
    }

    /// From 0.9 s, each 0.9 s beat rocks the tickets and runs a wave of hops left to right.
    @Test func lettersWaveWithTheTickets() {
        #expect(near(LaunchWave.rock(at: 0.89), 0))
        #expect(near(LaunchWave.rock(at: 0.9 + 0.27), 1))
        // The first letter is at the top of its hop 0.12 + 0.14 of the way into the beat.
        let top = 0.9 + (0.12 + 0.14) * 0.9
        #expect(near(LaunchWave.letter(0, at: top).offset, -7))
        #expect(near(LaunchWave.letter(7, at: top).offset, 0))
        let lastTop = top + 7 * 0.045 * 0.9
        #expect(near(LaunchWave.letter(7, at: lastTop).offset, -7))
        #expect(near(LaunchWave.letter(0, at: top + 0.9).offset, -7))
    }
}

struct ShopfrontTests {
    /// The shops' glass, brass and steel, from the App Store screenshots' storefronts (2026-11-08).
    @Test func theShopsAreTheScreenshots() {
        #expect(
            [Palette.shopGlass, Palette.shopKnob, Palette.shutter, Palette.shutterSeam, Palette.shutterMark].map(\.hex)
                == ["#E3EDF4", "#F6C344", "#C3C7CF", "#B4B9C2", "#8A8F9A"])
    }

    /// The street's sky and paving, from the approved 商店街 (2026-11-08).
    @Test func theStreetIsTheApprovedOne() {
        #expect(
            [Palette.streetSky, Palette.pavement, Palette.paveJoint, Palette.kerb].map(\.hex)
                == ["#EEF2F7", "#E6E2DA", "#DCD7CE", "#CFCAC0"])
    }
}
