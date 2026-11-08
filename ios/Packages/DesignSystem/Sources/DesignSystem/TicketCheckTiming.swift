import Foundation

/// The approved "done" moment (`TicketCheck`, 2026-11-08), as a pure function of time: the
/// logo's two tickets bounce once as `TicketRock` rocks, the W on the front ticket fades, a white
/// check draws in where it was, then the words under it fade up. Played once; with Reduce Motion
/// it shows its last frame.
public enum TicketCheckTiming {
    /// One frame of it: each part from 0 (not started) to 1 (done).
    public struct Frame: Equatable, Sendable {
        /// How far into the bounce the tickets are, as `TicketRock.amount` says.
        public var rock: Double
        /// How much of the W shows: 1 at first, 0 once it has faded.
        public var letter: Double
        /// How much of the check is drawn.
        public var check: Double
        /// How far the words under it have faded up.
        public var words: Double

        /// The last frame: the check, without the W, and the words.
        public static let done = Frame(rock: 0, letter: 0, check: 1, words: 1)
    }

    /// When it ends, in seconds; the moment after can follow then.
    public static let duration = 1.43

    /// The bounce, the W's fade, the check's stroke and the words, in seconds from the start.
    static let bounce = 0.0..<0.61
    static let fade = 0.68..<0.92
    static let stroke = 0.88..<1.36
    static let rise = 1.02..<1.43

    public static func frame(at time: Double) -> Frame {
        guard time < duration else { return .done }
        let bounced = progress(time, through: bounce)
        // The rock's own beat runs 0.9 s with its rest after 0.6: one beat is the bounce.
        let rock = bounced < 1 ? TicketRock.amount(at: bounced * TicketRock.settle * TicketRock.beat) : 0
        return Frame(
            rock: rock,
            letter: 1 - progress(time, through: fade),
            check: Tween.cubicOut(progress(time, through: stroke)),
            words: Tween.cubicOut(progress(time, through: rise)))
    }

    private static func progress(_ time: Double, through span: Range<Double>) -> Double {
        min(max((time - span.lowerBound) / (span.upperBound - span.lowerBound), 0), 1)
    }
}
