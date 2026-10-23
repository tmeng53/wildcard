#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

extension Haptic {
    /// The system feedback behind each haptic. iOS skips it when the person has turned system
    /// haptics off.
    var feedback: SensoryFeedback {
        switch self {
        case .pick: .selection
        case .appear: .impact(weight: .light)
        case .refuse: .impact(flexibility: .soft, intensity: 0.4)
        case .tick: .impact(flexibility: .rigid, intensity: 0.35)
        case .checkIn: .impact(weight: .heavy)
        case .score: .impact(weight: .light, intensity: 0.6)
        case .land: .impact(weight: .medium)
        case .reaction: .impact(flexibility: .soft, intensity: 0.7)
        case .unbox: .impact(weight: .heavy)
        }
    }
}

extension View {
    /// Plays `haptic` whenever `trigger` changes.
    public func haptic(_ haptic: Haptic, trigger: some Equatable) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }

    /// Plays `haptic` when `trigger` changes and `condition` says this change deserves it.
    public func haptic<T: Equatable>(
        _ haptic: Haptic, trigger: T, condition: @escaping (_ old: T, _ new: T) -> Bool
    ) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger, condition: condition)
    }
}
#endif
