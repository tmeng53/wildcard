#if os(iOS)
import CheckInDomain
import DesignSystem
import DesignSystemUI

/// The design's stage: 390 (`StageLayout.width`) by 844 points, the screen it was drawn for.
enum Stage {
    static let height = 844.0

    /// The venue's parts people stand behind, by depth: the tennis net.
    static func fronts(of scene: SceneTheme) -> [Double] {
        scene == .tennis ? [388.5] : []
    }
}

extension StageStatus {
    /// The ring around the head and under the feet: closed once checked in (练了 or 请假条), grey
    /// with the moon on a planned rest day, open otherwise.
    var ring: RingStatus {
        switch self {
        case .trained, .disclaimer: .done
        case .restDay: .restDay
        case .notYet: .open
        }
    }
}
#endif
