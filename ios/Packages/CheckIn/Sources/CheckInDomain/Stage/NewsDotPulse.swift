/// How the unread dot on the sideline coach's phone pulses while its page has news (Tracy,
/// 2026-11-13: the dot alone was too easy to miss): every `period` a halo rings out of the dot and
/// fades while the dot swells and settles, so it keeps blinking until the cards are seen. The dot
/// itself never fades, so it reads at any moment; under Reduce Motion it stands still.
public struct NewsDotPulse: Hashable, Sendable {
    /// How long one pulse takes, in seconds; two fit in each of the coach's news whistles.
    public static let period: Double = CoachCue.newsWhistlePeriod / 2
    /// The part of a pulse the dot swells in, and the part the halo rings out in.
    static let swell: Double = 0.35
    static let ring: Double = 0.8

    /// The dot's size against its resting size.
    public let dotScale: Double
    /// The halo's size against the dot's, and how strongly it shows (0 is gone).
    public let haloScale: Double
    public let haloOpacity: Double

    public init(dotScale: Double, haloScale: Double, haloOpacity: Double) {
        self.dotScale = dotScale
        self.haloScale = haloScale
        self.haloOpacity = haloOpacity
    }

    /// The dot still, with no halo, as under Reduce Motion.
    public static let still = NewsDotPulse(dotScale: 1, haloScale: 1, haloOpacity: 0)

    /// The pulse `seconds` into any clock; it repeats every `period`.
    public static func at(_ seconds: Double) -> NewsDotPulse {
        let phase = (seconds / period - (seconds / period).rounded(.down))
        let dotScale = phase < swell ? 1 + 0.25 * bump(phase / swell) : 1
        guard phase < ring else { return NewsDotPulse(dotScale: dotScale, haloScale: 1, haloOpacity: 0) }
        let out = easeOut(phase / ring)
        return NewsDotPulse(dotScale: dotScale, haloScale: 1 + 1.6 * out, haloOpacity: 0.45 * (1 - out))
    }

    /// 0 at both ends, 1 in the middle.
    private static func bump(_ progress: Double) -> Double {
        4 * progress * (1 - progress)
    }

    private static func easeOut(_ progress: Double) -> Double {
        1 - (1 - progress) * (1 - progress)
    }
}
