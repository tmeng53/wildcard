import Foundation

/// The two-ticket loader's motion (design A 两张票): the logo's tickets rock apart and back on a
/// beat, the front one lifting, then rest until the next beat. A pure function of time, so the
/// loader draws it frame by frame and a test pins the curve.
public enum TicketRock {
    /// One rock and its rest, in seconds.
    public static let beat = 0.9
    /// How far through the beat the tickets are furthest apart, and back at rest.
    public static let peak = 0.3
    public static let settle = 0.6
    /// At the top of the rock: how far each ticket turns, in degrees, and how far the front one
    /// lifts, in the logo's units (it is drawn on a 100 × 100 grid).
    public static let backTurn = 6.0
    public static let frontTurn = -6.0
    public static let frontLift = 5.4
    /// How long the launch cover takes to fade once what it waits for is ready.
    public static let fadeOut = 0.3

    /// How far into the rock the tickets are at `time` seconds: 0 at rest, 1 at the top, a
    /// little past 1 as they overshoot.
    public static func amount(at time: Double) -> Double {
        let fraction = time.truncatingRemainder(dividingBy: beat) / beat
        if fraction < peak { return ease(fraction / peak) }
        if fraction < settle { return 1 - ease((fraction - peak) / (settle - peak)) }
        return 0
    }

    /// The approved design's easing between its keyframes, a gentle overshoot.
    private static func ease(_ progress: Double) -> Double {
        Tween.cubicBezier(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1, progress)
    }
}
