import Foundation

/// Easing curves for motion drawn frame by frame from a clock (a reveal, an entrance), where
/// a SwiftUI spring can't be sampled. Each maps progress 0…1 to eased progress, as the
/// approved prototypes compute it, so a timeline ported from one matches it frame for frame.
public enum Tween {
    /// Fast, then settling: 1 − (1 − f)³.
    public static func cubicOut(_ progress: Double) -> Double { 1 - pow(1 - progress, 3) }

    /// Slow, then fast, as something falls: f².
    public static func quadIn(_ progress: Double) -> Double { progress * progress }

    /// Slow at both ends.
    public static func cubicInOut(_ progress: Double) -> Double {
        progress < 0.5 ? 4 * progress * progress * progress : 1 - pow(-2 * progress + 2, 3) / 2
    }

    /// Past the end and back: the overshoot of something landing in place.
    public static func backOut(_ progress: Double) -> Double {
        let overshoot = 1.7
        return 1 + (overshoot + 1) * pow(progress - 1, 3) + overshoot * pow(progress - 1, 2)
    }

    /// A landing's squash: a damped wobble from 1 down to 0, multiplied into how far it squashes.
    public static func squash(_ progress: Double) -> Double {
        progress >= 1 ? 0 : exp(-5 * progress) * cos(progress * 14)
    }

    /// How far `time` is through a span starting at `start` and lasting `duration`, from 0 to 1.
    public static func progress(_ time: Double, from start: Double, lasting duration: Double) -> Double {
        min(1, max(0, (time - start) / duration))
    }

    /// From `start` to `end` by `fraction`.
    public static func mix(_ start: Double, _ end: Double, _ fraction: Double) -> Double {
        start + (end - start) * fraction
    }
}

extension Tween {
    /// CSS's `ease-in-out`, cubic-bezier(0.42, 0, 0.58, 1): how a CSS keyframe animation eases
    /// between its keyframes by default.
    public static func easeInOut(_ progress: Double) -> Double {
        cubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1, progress)
    }

    /// A CSS cubic-bezier timing function at `progress`, solved the way browsers do: find the
    /// curve's parameter whose x is `progress`, then read its y.
    public static func cubicBezier(
        x1: Double, y1: Double, x2: Double, y2: Double, _ progress: Double  // swiftlint:disable:this identifier_name
    ) -> Double {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return 1 }
        func coordinate(_ time: Double, _ first: Double, _ second: Double) -> Double {
            ((1 + 3 * first - 3 * second) * time + (3 * second - 6 * first)) * time * time + 3 * first * time
        }
        var (low, high, time) = (0.0, 1.0, progress)
        for _ in 0..<40 {
            let value = coordinate(time, x1, x2)
            if abs(value - progress) < 1e-6 { break }
            if value < progress { low = time } else { high = time }
            time = (low + high) / 2
        }
        return coordinate(time, y1, y2)
    }
}

/// The wiggle of a picked carton (approved 2026-10-22): a quick shake about the middle of its
/// base the moment it is picked, then still, every 2.4 s while it stays picked.
public enum Wiggle {
    public static let period = 2.4
    /// The keyframes: (fraction of the period, degrees clockwise), each eased in and out.
    static let keys: [(at: Double, degrees: Double)] = [
        (0, 0), (0.04, -7), (0.08, 6), (0.12, -4), (0.16, 2), (0.2, 0), (1, 0),
    ]

    /// The carton's turn `time` seconds after it was picked.
    public static func degrees(at time: Double) -> Double {
        let phase = (time.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
        let fraction = phase / period
        for (start, end) in zip(keys, keys.dropFirst()) where fraction < end.at {
            let eased = Tween.easeInOut((fraction - start.at) / (end.at - start.at))
            return Tween.mix(start.degrees, end.degrees, eased)
        }
        return 0
    }
}
