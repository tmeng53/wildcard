import Contracts
import Foundation

/// Someone pulled the cord at night (开灯, the approved prototype of 2026-10-24), as a pure
/// function of the seconds since. Switched on: the lamps flicker on, the dark lifts in two steps
/// with a faint flash at each, and the sleepers wake one after another, annoyed (the `woken` move),
/// the first of them mumbling a line. Switched off: the dark comes back and everyone awake dozes
/// off. Only on this phone, until the night ends (`night(at:in:)`).
public struct LightsFlip: Hashable, Sendable {
    /// Which way the lights went.
    public let isOn: Bool
    /// Under Reduce Motion: no flicker, flash or line, a short crossfade and poses swapping at once.
    public let reduceMotion: Bool

    public init(isOn: Bool, reduceMotion: Bool) {
        self.isOn = isOn
        self.reduceMotion = reduceMotion
    }

    /// When the first sleeper starts waking, and how long after each the next one does.
    public static let wakeStart = 0.45
    public static let wakeStagger = 0.1
    /// How long `woken` plays, the move that ends standing up (`AvatarArt`'s `moves/woken.json`).
    public static let wokenDuration = 2.5
    /// When the first sleeper says their line; it stays up `Motion.speechHold`.
    public static let lineAt = 1.7
    /// How long switching off takes to go dark: the dark lifts or falls this fast.
    static let fade = 0.3

    /// How dark the scene is, 0 (day) to 1 (the night layer in full).
    public func darkness(at seconds: Double) -> Double {
        if isOn {
            if reduceMotion { return seconds < Self.reducedFade ? 1 - seconds / Self.reducedFade : 0 }
            if seconds < 0.2 { return 1 }
            if seconds < 0.32 { return 1 - 0.5 * smooth((seconds - 0.2) / 0.12) }
            if seconds < 0.42 { return 0.5 }
            if seconds < 0.42 + Self.fade {
                let progress = (seconds - 0.42) / Self.fade
                return 0.5 * (1 - (1 - (1 - progress) * (1 - progress)))
            }
            return 0
        }
        let fade = reduceMotion ? Self.reducedFade : Self.fade
        return seconds < fade ? smooth(max(0, seconds) / fade) : 1
    }

    /// How brightly the lamp tubes show over the lifting dark: on, off, on, then fading into the
    /// day art.
    public func lamps(at seconds: Double) -> Double {
        guard isOn, !reduceMotion else { return 0 }
        switch seconds {
        case ..<0.06: return 0
        case ..<0.11: return 1
        case ..<0.17: return 0.15
        case ..<0.24: return 1
        case ..<0.6: return 1 - (seconds - 0.24) / 0.36
        default: return 0
        }
    }

    /// A flat white flash as each bank of lamps comes on, at 0.2 and 0.42 seconds.
    public func flash(at seconds: Double) -> Double {
        guard isOn, !reduceMotion else { return 0 }
        func pulse(_ start: Double) -> Double {
            seconds >= start && seconds < start + 0.12 ? 0.1 * (1 - (seconds - start) / 0.12) : 0
        }
        return pulse(0.2) + pulse(0.42)
    }

    /// When the sleeper `index` (in the squad's order) starts waking; everyone at once under
    /// Reduce Motion, and when switching off.
    public func start(ofSleeper index: Int) -> Double {
        isOn && !reduceMotion ? Self.wakeStart + Double(index) * Self.wakeStagger : 0
    }

    /// How asleep sleeper `index` looks, 1 to 0, for their "z z": they fade as each wakes, and
    /// come back once the doze has dropped them off (`dozeDuration` seconds).
    public func sleep(ofSleeper index: Int, at seconds: Double, dozeDuration: Double) -> Double {
        if isOn { return max(0, min(1, 1 - (seconds - start(ofSleeper: index)) / 0.15)) }
        if reduceMotion { return 1 }
        return max(0, min(1, (seconds - dozeDuration) / Self.fade))
    }

    /// How much of a 请假条 sleeper `index` shows: it comes back up once they have stood up and
    /// goes away at once when they doze off.
    public func sign(ofSleeper index: Int, at seconds: Double) -> Double {
        if reduceMotion { return isOn ? 1 : 0 }
        if isOn { return max(0, min(1, (seconds - start(ofSleeper: index) - Self.wokenDuration) / 0.2)) }
        return max(0, 1 - seconds / 0.2)
    }

    /// Whether the first sleeper's line is up: from `lineAt` for `hold` seconds, only when the
    /// lights came on with motion.
    public func showsLine(at seconds: Double, hold: Double) -> Bool {
        isOn && !reduceMotion && seconds >= Self.lineAt && seconds < Self.lineAt + hold
    }

    /// Reduce Motion's crossfade.
    static let reducedFade = 0.2

    private func smooth(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
    }

    /// The night a moment belongs to, named by the day it began, in `timeZone`:
    /// 23:00 begins it and 6:00 the next morning ends it. Nil by day. The lights a member switched
    /// on are kept with their night, so the next night starts dark again.
    public static func night(at date: Date, in timeZone: TimeZone) -> LocalDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard DayPhase(hour: calendar.component(.hour, from: date)) == .night,
            let began = calendar.date(byAdding: .hour, value: -DayPhase.dayStarts, to: date)
        else { return nil }
        let day = calendar.dateComponents([.year, .month, .day], from: began)
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day else { return nil }
        return try? LocalDay(year: year, month: month, day: dayOfMonth)
    }
}
