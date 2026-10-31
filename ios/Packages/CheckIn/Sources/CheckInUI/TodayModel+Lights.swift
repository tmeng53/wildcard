#if os(iOS)
import CheckInDomain
import Foundation

/// 开灯: the light cord at night (the approved prototype of 2026-10-24).
extension TodayModel {
    /// A pull of the light cord at night: which way the lights went, and when on the screen's
    /// clock, for the scene to play (`LightsFlip`).
    struct LightsPull: Equatable {
        let isOn: Bool
        let start: Date
    }

    /// Where this phone keeps the night the member switched the lights on for (`LocalDay`'s
    /// description of the day it began).
    static let lightsKey = "today.lightsOn"

    /// Whether the member switched the lights on tonight. Only on this phone and only for them:
    /// nothing goes to the squad, and the next night starts dark.
    var lightsOn: Bool {
        guard let night = LightsFlip.night(at: now(), in: timeZone) else { return false }
        return litNight == night.description
    }

    /// The phase the squad lives in: the day's, once the lights are on at night. The scene
    /// still knows it is night, for the cord.
    var stagePhase: DayPhase { lightsOn ? .day : phase }

    /// The cord was pulled: the lights go on, or off again. The sleepers wake (or doze off) and
    /// tapping them tells what they're up to today; only switching on plays `Haptic.lights`.
    func pullCord(reduceMotion: Bool) {
        guard let night = LightsFlip.night(at: now(), in: timeZone) else { return }
        let isOn = !lightsOn
        litNight = isOn ? night.description : nil
        if isOn {
            defaults.set(night.description, forKey: Self.lightsKey)
        } else {
            defaults.removeObject(forKey: Self.lightsKey)
        }
        pats.dismissBubble()
        lightsPull = LightsPull(isOn: isOn, start: .now)
        cast.switchLights(LightsFlip(isOn: isOn, reduceMotion: reduceMotion))
    }
}
#endif
