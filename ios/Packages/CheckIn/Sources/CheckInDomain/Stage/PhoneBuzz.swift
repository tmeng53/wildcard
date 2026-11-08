/// The coach's phone buzzing while a morning note waits (the approved 毛头的手机来消息): every
/// `period` seconds the phone shows two buzz lines and the coach hops a little and sways as it
/// glances down at it, as a pure function of time. Under Reduce Motion only the dot shows.
public enum PhoneBuzz {
    /// One buzz and glance, in seconds.
    public static let period: Double = 3
    /// How high the hop goes, in rig points (a 320-point canvas).
    static let hopHeight: Double = 15
    /// How far the sway turns, in degrees.
    static let swayAngle: Double = 2

    /// How far up the coach is at `seconds`, in rig points.
    public static func hop(at seconds: Double) -> Double {
        hopHeight * curve([(0.08, 0), (0.12, 1), (0.16, 0)], at: seconds)
    }

    /// How far the coach turns at `seconds`, in degrees, clockwise.
    public static func sway(at seconds: Double) -> Double {
        swayAngle * curve([(0.12, 0), (0.16, -1), (0.20, 1), (0.24, -1), (0.28, 0)], at: seconds)
    }

    /// How much the buzz lines show at `seconds`, from 0 to 1.
    public static func lines(at seconds: Double) -> Double {
        curve([(0.08, 0), (0.12, 1), (0.34, 1), (0.40, 0)], at: seconds)
    }

    /// The value at `seconds` of keyframes over one period, at fractions of it, straight between
    /// them and held at the first and last outside.
    private static func curve(_ keys: [(at: Double, value: Double)], at seconds: Double) -> Double {
        let cycle = seconds.truncatingRemainder(dividingBy: period)
        let fraction = (cycle < 0 ? cycle + period : cycle) / period
        guard let first = keys.first, let last = keys.last else { return 0 }
        if fraction <= first.at { return first.value }
        for (start, end) in zip(keys, keys.dropFirst()) where fraction <= end.at {
            return start.value + (end.value - start.value) * (fraction - start.at) / (end.at - start.at)
        }
        return last.value
    }
}
