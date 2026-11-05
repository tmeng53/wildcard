import Foundation

/// The launch cover's motion (design A 字母浪, 2026-11-04): it opens on the system's launch
/// screen, the logo alone at the centre; the logo lifts, WILDCARD's letters pop up under it one
/// after another, and from then on, on each of `TicketRock`'s beats, the tickets rock and the
/// letters hop in a wave. A pure function of the time since the cover appeared, so the cover
/// draws it frame by frame and a test pins it.
public enum LaunchWave {
    /// How far the logo lifts from the screen's centre, in points, and how long it takes.
    public static let lift = 30.0
    public static let liftDuration = 0.35
    /// When the first letter starts popping up, how much later each next one starts, how long
    /// each takes, and how far below its place it starts, in points.
    public static let letterStart = 0.1
    public static let letterStagger = 0.04
    public static let letterDuration = 0.35
    public static let letterDrop = 22.0
    /// When the tickets start rocking and the letters start their wave: the entrance is over.
    public static let waveStart = 0.9
    /// When, in each beat, the first letter hops, how much later each next one does, how long
    /// a hop takes (all as fractions of the beat) and how high it goes, in points.
    public static let hopStart = 0.12
    public static let hopStagger = 0.045
    public static let hopDuration = 0.28
    public static let hopHeight = 7.0
    /// How long the cover stays up at least, so the word has landed before it fades.
    public static let entrance = 0.8
    /// The word on the cover; it is the brand, so it isn't translated.
    public static let word = "WILDCARD"

    /// How far up the logo is at `time`, in points.
    public static func logoLift(at time: Double) -> Double {
        lift * ease(Tween.progress(time, from: 0, lasting: liftDuration))
    }

    /// How far into `TicketRock`'s rock the tickets are at `time`: still until the wave starts.
    public static func rock(at time: Double) -> Double {
        time < waveStart ? 0 : TicketRock.amount(at: time - waveStart)
    }

    /// Where letter `index` is at `time`: how far below its place, in points (negative while it
    /// hops above it), and how visible, from 0 to 1.
    public static func letter(_ index: Int, at time: Double) -> (offset: Double, opacity: Double) {
        let progress = Tween.progress(time, from: letterStart + letterStagger * Double(index), lasting: letterDuration)
        return ((1 - ease(progress)) * letterDrop - hop(index, at: time), min(1, progress * 3))
    }

    /// How high letter `index` hops at `time`, in points.
    static func hop(_ index: Int, at time: Double) -> Double {
        guard time >= waveStart else { return 0 }
        let beat = (time - waveStart).truncatingRemainder(dividingBy: TicketRock.beat) / TicketRock.beat
        let into = (beat - hopStart - hopStagger * Double(index)) / hopDuration
        guard into > 0, into < 1 else { return 0 }
        return sin(.pi * into) * hopHeight
    }

    /// The design's gentle overshoot, the same as the tickets'.
    private static func ease(_ progress: Double) -> Double {
        Tween.cubicBezier(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1, progress)
    }
}
