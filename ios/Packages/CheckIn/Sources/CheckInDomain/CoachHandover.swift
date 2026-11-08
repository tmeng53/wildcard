import Contracts
import DesignSystem
import Foundation

/// The coaches changing places on the home's sideline (换教练), as the approved 教练交接信 prototype
/// (version 3) plays it, a pure function of time: the coach that took over walks in from the left
/// and waits beside the sideline while the one that left writes under 「交接中」; once the letter is
/// written (or couldn't be), the old coach walks off to the left, the envelope flies out, and the
/// new coach steps onto its spot. Distances are stage points (the prototype's pixels on its
/// 340-point phone, scaled to the 390-point stage); times are seconds.
public struct CoachHandover: Hashable, Sendable {
    public let leaving: CoachSpeaker
    public let coming: CoachSpeaker
    /// When the captain confirmed.
    public let start: Date
    /// When the letter was written or failed; nil while the old coach writes.
    public private(set) var end: Date?
    /// The letter, once written; nil while writing, or when it couldn't be.
    public private(set) var letter: CoachLetter?

    public init(from leaving: CoachSpeaker, to coming: CoachSpeaker, start: Date) {
        (self.leaving, self.coming, self.start) = (leaving, coming, start)
    }

    /// The letter was written (or not) at `moment`: the coaches swap from then.
    public mutating func end(at moment: Date, letter: CoachLetter?) {
        guard end == nil else { return }
        end = moment
        self.letter = letter
    }

    /// The prototype's pixels in stage points.
    static let pixel = 390.0 / 340.0

    /// The new coach starts walking in, from off the left edge, then takes `walkIn`.
    public static let arrives = 0.3
    public static let walkIn = 1.4
    /// 「交接中」 shows over the old coach, which writes until the letter is done.
    public static let writes = 0.9
    public static let chipFade = 0.3
    /// The old coach walks off once the letter is done, taking `walkOff`.
    public static let walkOff = 1.3
    /// The envelope flies out this long after the old coach starts off.
    public static let envelopeAfter = 0.1
    /// The new coach steps onto the sideline this long after the old one starts off, taking `settle`.
    public static let settleAfter = 1.0
    public static let settle = 0.8

    /// Where the new coach waits, right of the sideline spot; and where it starts, off the left edge.
    static let beside = 61.0
    static let offstage = -50.0

    /// How far the old coach has walked off, at `date`: sideways and up off its spot.
    public func outgoing(at date: Date) -> (dx: Double, lift: Double) {
        guard let leaves = leavesAt else { return (0, 0) }
        let time = date.timeIntervalSince(leaves)
        guard time > 0 else { return (0, 0) }
        let eased = Tween.cubicBezier(x1: 0.5, y1: 0, x2: 0.8, y2: 0.6, min(1, time / Self.walkOff))
        // The prototype's keyframes: a hop, a step, another hop, then off the edge.
        let keys: [(at: Double, dx: Double, lift: Double)] = [
            (0, 0, 0), (0.2, 0, 6), (0.4, -30, 0), (0.6, -60, 6), (1, -140, 0),
        ]
        for (start, finish) in zip(keys, keys.dropFirst()) where eased <= finish.at {
            let part = (eased - start.at) / (finish.at - start.at)
            return (
                Tween.mix(start.dx, finish.dx, part) * Self.pixel, Tween.mix(start.lift, finish.lift, part) * Self.pixel
            )
        }
        return (-140 * Self.pixel, 0)
    }

    /// Whether the old coach is still on the stage at `date`.
    public func showsOutgoing(at date: Date) -> Bool {
        guard let leaves = leavesAt else { return true }
        return date.timeIntervalSince(leaves) < Self.walkOff
    }

    /// The old coach's writing, at `date`: a bob up and a tilt, every half second, until it leaves.
    public func scribble(at date: Date) -> (lift: Double, degrees: Double) {
        let time = date.timeIntervalSince(start)
        guard time > Self.writes, leavesAt.map({ date < $0 }) ?? true else { return (0, 0) }
        let phase = (time - Self.writes).truncatingRemainder(dividingBy: 0.5) / 0.5
        let swing = Tween.easeInOut(phase < 0.5 ? phase * 2 : 2 - phase * 2)
        return (2 * Self.pixel * swing, -2 * swing)
    }

    /// How much 「交接中」 shows at `date`, 0 to 1.
    public func chip(at date: Date) -> Double {
        let shown = Tween.progress(date.timeIntervalSince(start), from: Self.writes, lasting: Self.chipFade)
        guard let leaves = leavesAt else { return shown }
        return shown * (1 - Tween.progress(date.timeIntervalSince(leaves), from: 0, lasting: Self.chipFade))
    }

    /// How far right of the sideline spot the new coach is at `date`.
    public func incoming(at date: Date, sideline: StagePoint) -> Double {
        let walk = Tween.cubicBezier(
            x1: 0.3, y1: 0.7, x2: 0.4, y2: 1,
            Tween.progress(date.timeIntervalSince(start), from: Self.arrives, lasting: Self.walkIn))
        let waiting = Tween.mix(Self.offstage - sideline.x, Self.beside, walk)
        guard let settles = settlesAt else { return waiting }
        let step = Tween.cubicBezier(
            x1: 0.3, y1: 1.2, x2: 0.4, y2: 1,
            Tween.progress(date.timeIntervalSince(settles), from: 0, lasting: Self.settle))
        return Tween.mix(waiting, 0, step)
    }

    /// When the old coach starts off: once the letter is done, and not before it started writing.
    public var leavesAt: Date? {
        end.map { max($0, start.addingTimeInterval(Self.writes)) }
    }

    /// When the envelope flies out; nil without a letter.
    public var envelopeAt: Date? {
        guard letter != nil else { return nil }
        return leavesAt?.addingTimeInterval(Self.envelopeAfter)
    }

    /// When the new coach steps onto the spot: after the old one starts off, and once it has walked in.
    var settlesAt: Date? {
        leavesAt.map {
            max($0.addingTimeInterval(Self.settleAfter), start.addingTimeInterval(Self.arrives + Self.walkIn))
        }
    }

    /// When it has all played out, and the new coach simply stands on the sideline.
    public var finishesAt: Date? {
        settlesAt.map { max($0.addingTimeInterval(Self.settle), leavesAt?.addingTimeInterval(Self.walkOff) ?? $0) }
    }
}
