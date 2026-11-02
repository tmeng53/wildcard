import Foundation

/// How the app shows a wait (loader design A 三拍, approved 2026-10-24): one language everywhere.
/// A whole page waits with the character jogging in place; a button or a line waits with three
/// dots hopping in a running cadence, in the colour of what they replace. Neither says a word, and
/// neither shows for a wait too short to notice.
public enum Loading {
    /// A whole page's loader shows only once the wait has lasted this long, in seconds.
    public static let pageDelay: Double = 0.5
    /// A button's or a line's loader shows only once the wait has lasted this long, in seconds. The
    /// control stops taking taps at once.
    public static let inlineDelay: Double = 0.3
    /// A loader that showed stays at least this long, in seconds, so it never blinks.
    public static let minimumShown: Double = 0.6
    /// A request still unanswered after this long, in seconds, has failed: the page shows its
    /// error, and 编几句 falls back to the dice lines.
    public static let giveUpAfter: Double = 15

    /// What the wait will replace (the lines on offer while 编几句 writes) fades to this opacity.
    public static let waitingOpacity: Double = 0.35

    /// How much longer a loader that has shown for `shown` seconds stays once the wait is over.
    public static func hold(afterShowing shown: Double) -> Double {
        max(0, minimumShown - shown)
    }

    // MARK: - 三拍

    /// Each dot's diameter, in points.
    public static let dot: Double = 6
    /// Between the dots, in points.
    public static let dotGap: Double = 4
    /// How high a dot hops, in points.
    public static let dotRise: Double = 5
    /// One hop of all three, in seconds.
    public static let dotCycle: Double = 0.9
    /// Each dot hops this long after the one on its left, in seconds.
    public static let dotStagger: Double = 0.12
    /// A dot's opacity at rest; it is fully opaque at the top of its hop.
    public static let dotRestOpacity: Double = 0.35
    /// The dots' width, in points.
    public static let dotsWidth = 3 * dot + 2 * dotGap

    /// How far up the hop dot `index` (0, 1 or 2, left to right) is at `time` seconds, from 0 at
    /// rest to 1 at the top: up in the first quarter of its cycle, down by 60%, then at rest.
    public static func hop(dot index: Int, at time: Double) -> Double {
        let local = (time - Double(index) * dotStagger).truncatingRemainder(dividingBy: dotCycle)
        let phase = (local < 0 ? local + dotCycle : local) / dotCycle
        if phase < 0.25 { return Tween.cubicOut(phase / 0.25) }
        if phase < 0.6 { return 1 - Tween.cubicOut((phase - 0.25) / 0.35) }
        return 0
    }

    /// Dot `index`'s opacity at `time`: brighter as it rises.
    public static func dotOpacity(dot index: Int, at time: Double) -> Double {
        dotRestOpacity + (1 - dotRestOpacity) * hop(dot: index, at: time)
    }

    // MARK: - The page's character

    /// The character jogs in place at this fraction of the run's own tempo.
    public static let jogTempo: Double = 0.85

    // MARK: - What arrives

    /// What the wait was for, arriving: rising this many points as it fades in over
    /// `arrival`, each line `arrivalStagger` after the one above.
    public static let arrivalRise: Double = 6
    public static let arrival = MotionCurve(duration: 0.35, 0.2, 0.8, 0.2, 1)
    public static let arrivalStagger: Double = 0.08
}
