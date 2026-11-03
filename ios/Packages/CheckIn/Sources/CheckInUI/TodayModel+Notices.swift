#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import Foundation

/// News nobody on the scene can tell, in a `NoticeBanner` at the top of 今天: so far, a teammate
/// moving the squad to another scene.
extension TodayModel {
    /// One notice on the home: so far, the squad moved to `scene`.
    struct Notice: Identifiable, Equatable {
        let scene: SceneTheme
        /// Who moved it, by nickname; nil when the home doesn't know them.
        let picker: String?
        /// Bumps for each notice, so the same news told twice drops in again.
        let id: Int
    }

    /// Puts the home on the squad's `scene` as read from the server, telling `move` if a
    /// teammate made one.
    public func land(on scene: SceneTheme, move: SceneMove?) async {
        if let move {
            await tell(move)
        } else {
            self.scene = scene
        }
    }

    /// A teammate moved the squad: on the scene, the squad drops onto the new one, as after a
    /// pick; then the banner says who moved it. In the middle of a check-in, the scene just
    /// changes under it and the banner waits.
    func tell(_ move: SceneMove) async {
        if step == .scene {
            await dropIn(on: move.scene, coveredAt: .now)
        } else {
            scene = move.scene
        }
        let name = move.picker.flatMap { picker in cast.mates.first { $0.id == picker }?.name }
        noticeCount += 1
        pendingNotices.append(Notice(scene: move.scene, picker: name, id: noticeCount))
        Task { await showNextNotice() }
    }

    /// The next notice waiting, once the squad has landed and the scene is in view: not while a
    /// check-in is being written or the burst is open, when it waits for the next load.
    func showNextNotice() async {
        await untilArrived()
        guard notice == nil, step == .scene, !isBurstOpen, !pendingNotices.isEmpty else { return }
        notice = pendingNotices.removeFirst()
    }
}
#endif
