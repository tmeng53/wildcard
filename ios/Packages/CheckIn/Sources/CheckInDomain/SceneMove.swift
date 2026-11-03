import Contracts
import DesignSystem

/// A teammate moved the squad to another scene since this phone last showed it: 今天 drops the
/// squad onto it and a `NoticeBanner` says who did (Tracy, 2026-11-02: an in-app notice, no
/// push). Told once, since the phone keeps the scene it showed.
public struct SceneMove: Equatable, Sendable {
    public let scene: SceneTheme
    /// Who picked it; nil once they deleted their account.
    public let picker: MemberID?

    public init(scene: SceneTheme, picker: MemberID?) {
        self.scene = scene
        self.picker = picker
    }

    /// The move from `kept`, the scene this phone last showed, to the squad's scene now, as
    /// `member` sees it. Nothing to tell on a phone that never showed the squad, when the scene
    /// is the same, or when the member picked it themselves (they watched it land).
    public init?(from kept: SceneTheme?, to now: SquadScene, member: MemberID) {
        guard let kept, let scene = SceneTheme(rawValue: now.scene.rawValue), scene != kept else { return nil }
        let picker = now.picked.flatMap { $0.scene == now.scene ? $0.picker : nil }
        guard picker != member else { return nil }
        self.init(scene: scene, picker: picker)
    }
}
