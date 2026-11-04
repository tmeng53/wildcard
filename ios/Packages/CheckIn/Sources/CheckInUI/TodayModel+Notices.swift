#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import Foundation

/// News nobody on the scene can tell, in a `NoticeBanner` at the top of 今天: a teammate moving
/// the squad to another scene, a store or prop the member's training unlocked, and a notice we sent
/// every member (群发通知).
extension TodayModel {
    /// What a notice tells.
    enum NoticeNews: Equatable {
        /// The squad moved to the scene, by the picker's nickname (nil when the home doesn't know
        /// them).
        case moved(SceneTheme, picker: String?)
        /// A 练了 opened a store or a prop.
        case unlocked(Unlock)
        /// A notice we sent every member, told on this phone once.
        case broadcast(Broadcast)
    }

    /// One notice on the home.
    struct Notice: Identifiable, Equatable {
        let news: NoticeNews
        /// New for each notice, so the same news told twice drops in again.
        let id = UUID()
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
        pendingNotices.append(Notice(news: .moved(move.scene, picker: name)))
        Task { await showNextNotice() }
    }

    /// From now on, tells each store and prop the member's training opens with `notices`,
    /// starting with any already waiting.
    public func tellUnlocks(with notices: UnlockNotices) {
        unlockNotices = notices
        tellUnlocks()
    }

    /// The stores and props the member's training opened that the home hasn't told, one banner
    /// each, the earliest first. Without `unlockNotices` they wait.
    func tellUnlocks() {
        guard unlockNotices != nil else { return }
        let unlocks = store.takeUnlocks()
        guard !unlocks.isEmpty else { return }
        pendingNotices += unlocks.map { Notice(news: .unlocked($0)) }
        Task { await showNextNotice() }
    }

    /// Tells `broadcast` in a banner, after any notice already waiting; a tap opens its button's
    /// place through `open`, as its 通知 row does.
    public func tell(_ broadcast: Broadcast, open: @escaping (AppDestination) -> Void) {
        openDestination = open
        pendingNotices.append(Notice(news: .broadcast(broadcast)))
        Task { await showNextNotice() }
    }

    /// How long `notice` stays: one with a button stays until it is tapped or swiped away.
    func hold(_ notice: Notice) -> Double? {
        if case .broadcast(let broadcast) = notice.news, broadcast.action != nil { return nil }
        return noticeHold
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
