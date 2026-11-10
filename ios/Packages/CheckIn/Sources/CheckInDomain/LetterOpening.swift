import DesignSystem
import Foundation

/// The coach's letter on 今天 (交接信), as the approved 教练交接信 prototype (version 3) plays it, a
/// pure function of time: the envelope flies in and its seal pulses until tapped; then the seal
/// pops, the flap opens, the letter slides out and up, the envelope drops away and the letter
/// unfolds to its full size, with 收下 under it. Times are seconds; each part's progress runs
/// 0 to 1 by the prototype's own curve (a spring's may pass 1).
public struct LetterOpening: Hashable, Sendable {
    /// When the envelope started flying in.
    public let shown: Date
    /// When the seal was tapped; nil until then.
    public private(set) var opened: Date?

    public init(shown: Date, opened: Date? = nil) {
        self.shown = shown
        self.opened = opened
    }

    /// The seal was tapped: once, and only once the envelope has landed.
    public mutating func open(at moment: Date) {
        guard opened == nil, moment.timeIntervalSince(shown) >= Self.flight else { return }
        opened = moment
    }

    public static let flight = 0.75
    public static let scrimFade = 0.4
    /// The seal's pulse while it waits for a tap.
    public static let pulse = 1.0
    /// When it starts pulsing: as the envelope settles, a little after its flight.
    static let pulseFrom = 0.9
    static let pulseGrowth = 0.08

    // After the tap.
    static let sealPop = 0.25
    static let flapOpens = 0.2
    static let flapFolds = 0.26
    static let letterShows = 0.47
    static let backFlapFolds = 0.3
    static let rises = 0.8
    static let rise = 0.7
    static let unclips = 1.5
    static let drops = 1.51
    static let drop = 0.55
    static let unfolds = 1.58
    static let unfold = 0.75
    static let grows = 1.68
    static let grow = 0.6
    static let buttonShows = 2.08
    static let buttonFade = 0.3

    /// How far the envelope has flown in from its coach, past 1 as it springs into place.
    public func flight(at date: Date) -> Double {
        Tween.cubicBezier(
            x1: 0.2, y1: 1.2, x2: 0.4, y2: 1,
            Tween.progress(date.timeIntervalSince(shown), from: 0, lasting: Self.flight))
    }

    /// How dark the scene behind is, 0 to 1.
    public func scrim(at date: Date) -> Double {
        Tween.progress(date.timeIntervalSince(shown), from: 0, lasting: Self.scrimFade)
    }

    /// The seal's size and how much of it shows: pulsing once the envelope has landed, popping
    /// away when tapped.
    public func seal(at date: Date) -> (scale: Double, opacity: Double) {
        guard let opened else {
            let time = date.timeIntervalSince(shown) - Self.pulseFrom
            guard time > 0 else { return (1, 1) }
            let phase = time.truncatingRemainder(dividingBy: Self.pulse) / Self.pulse
            return (1 + Self.pulseGrowth * Tween.easeInOut(phase < 0.5 ? phase * 2 : 2 - phase * 2), 1)
        }
        let pop = ease(Tween.progress(date.timeIntervalSince(opened), from: 0, lasting: Self.sealPop))
        return (Tween.mix(1, 1.25, pop), 1 - pop)
    }

    /// The front flap's turn about the envelope's top edge, in degrees: 0 shut, 90 edge on; nil
    /// once it has folded past, and the back flap shows instead.
    public func frontFlap(at date: Date) -> Double? {
        guard let opened else { return 0 }
        let time = date.timeIntervalSince(opened)
        guard time < Self.letterShows else { return nil }
        return 90
            * Tween.cubicBezier(
                x1: 0.5, y1: 0, x2: 1, y2: 1, Tween.progress(time, from: Self.flapOpens, lasting: Self.flapFolds))
    }

    /// The back flap's turn, from 90 (edge on) to 180 (open above the envelope); nil until it shows.
    public func backFlap(at date: Date) -> Double? {
        guard let opened, case let time = date.timeIntervalSince(opened), time >= Self.letterShows else { return nil }
        return 90 + 90
            * Tween.cubicBezier(
                x1: 0, y1: 0, x2: 0.4, y2: 1, Tween.progress(time, from: Self.letterShows, lasting: Self.backFlapFolds))
    }

    /// Whether the letter is out of the envelope's inside yet.
    public func showsLetter(at date: Date) -> Bool {
        opened.map { date.timeIntervalSince($0) >= Self.letterShows } ?? false
    }

    /// How far the letter has slid up out of the envelope.
    public func rise(at date: Date) -> Double {
        part(date, from: Self.rises, lasting: Self.rise) { Tween.cubicBezier(x1: 0.3, y1: 1.1, x2: 0.4, y2: 1, $0) }
    }

    /// Whether the envelope's pocket still hides the letter's lower part.
    public func clipsLetter(at date: Date) -> Bool {
        opened.map { date.timeIntervalSince($0) < Self.unclips } ?? true
    }

    /// How far the empty envelope has dropped away, off the bottom of the screen at 1.
    public func drop(at date: Date) -> Double {
        part(date, from: Self.drops, lasting: Self.drop) { Tween.cubicBezier(x1: 0.5, y1: 0, x2: 0.8, y2: 0.4, $0) }
    }

    /// Whether the envelope is still there to draw: until it has dropped off the bottom of the
    /// screen, after which it is gone, so nothing off screen stays on the page or its accessibility.
    public func showsEnvelope(at date: Date) -> Bool {
        opened.map { date.timeIntervalSince($0) < Self.drops + Self.drop } ?? true
    }

    /// How far the letter has moved to its full place and size, and how far it has grown to its
    /// full height.
    public func unfold(at date: Date) -> (place: Double, height: Double) {
        (
            part(date, from: Self.unfolds, lasting: Self.unfold) {
                Tween.cubicBezier(x1: 0.3, y1: 1.15, x2: 0.4, y2: 1, $0)
            },
            part(date, from: Self.grows, lasting: Self.grow) { Tween.cubicBezier(x1: 0.3, y1: 1, x2: 0.4, y2: 1, $0) }
        )
    }

    /// How much 收下 shows, 0 to 1.
    public func button(at date: Date) -> Double {
        part(date, from: Self.buttonShows, lasting: Self.buttonFade, ease)
    }

    /// Whether it has all played out, the letter open in full.
    public func isOpen(at date: Date) -> Bool {
        opened.map { date.timeIntervalSince($0) >= Self.buttonShows + Self.buttonFade } ?? false
    }

    private func part(_ date: Date, from start: Double, lasting duration: Double, _ curve: (Double) -> Double)
        -> Double
    {
        guard let opened else { return 0 }
        return curve(Tween.progress(date.timeIntervalSince(opened), from: start, lasting: duration))
    }

    /// CSS's `ease`, the default of a transition.
    private func ease(_ progress: Double) -> Double {
        Tween.cubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1, progress)
    }
}
