import Foundation

/// How the pull cord moves, from the approved 开灯 prototype (2026-10-24): pulled down it
/// follows the finger with resistance up to `maxPull`, clicks at `clickPull`, and on release
/// springs back past its rest and swings, at most 5°. A tap pulls it `tapPull` by itself.
/// Offsets are in points, down from rest; angles in degrees, clockwise.
public enum PullCordMotion {
    /// The chain's length at rest, from where it hangs to the bulb's cap.
    public static let length = 70.0
    /// The furthest the cord follows a drag.
    public static let maxPull = 36.0
    /// How far down it has to go to click.
    public static let clickPull = 24.0
    /// A tap's pull: this far down, over `tapDuration` seconds, then the click and the release.
    public static let tapPull = 28.0
    public static let tapDuration = 0.12
    /// How long a release springs and swings before the cord is still.
    public static let releaseDuration = 2.0
    /// A drag shorter than this, in points, is a tap.
    public static let tapSlop = 4.0

    /// Where the cord is while the finger has dragged it `distance` points down: it gives less
    /// the further it goes, and stops at `maxPull`.
    public static func pull(dragged distance: Double) -> Double {
        let down = max(0, distance)
        return min(maxPull, maxPull * (1 - exp(-down / maxPull)) * 1.25)
    }

    /// Where a tap's pull is `seconds` into it, easing down to `tapPull`.
    public static func tap(at seconds: Double) -> Double {
        let progress = min(1, max(0, seconds / tapDuration))
        return tapPull * progress * progress * (3 - 2 * progress)
    }

    /// The cord `seconds` after it was let go `from` that far down: it springs back up, a little
    /// past rest, and swings side to side, both dying away. Without `swings` (Reduce Motion) it
    /// springs straight. Still once `releaseDuration` has passed.
    public static func release(from pull: Double, at seconds: Double, swings: Bool = true) -> (
        offset: Double, degrees: Double
    ) {
        guard seconds >= 0, seconds < releaseDuration else { return (0, 0) }
        let offset = max(-6, pull * exp(-7 * seconds) * cos(15 * seconds))
        let degrees = swings ? 5 * exp(-2.6 * seconds) * sin(9 * seconds) : 0
        return (offset, degrees)
    }
}
