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
    }
}
