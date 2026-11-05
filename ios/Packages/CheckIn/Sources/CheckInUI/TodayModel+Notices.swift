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
        /// What waited after two in a row, in one banner that opens 通知 (approved C, 2026-11-05).
        case more
    }

    /// One notice on the home.
    struct Notice: Identifiable, Equatable {
        let news: NoticeNews
        /// New for each notice, so the same news told twice drops in again.
        let id = UUID()

        /// A broadcast's button never folds into 「还有新通知」, so it can still be tapped on 今天.
        var hasButton: Bool {
            if case .broadcast(let broadcast) = news { return broadcast.action != nil }
            return false
        }
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
    /// each, the earliest first; pieces that came to one store together share one, which opens all
    /// their boxes. Without `unlockNotices` they wait.
    func tellUnlocks() {
        guard unlockNotices != nil else { return }
        var stores: Set<Substring> = []
        let unlocks = store.takeUnlocks().filter { unlock in
            // The art names each piece `<store>-<piece>`.
            guard unlock.kind == .piece, let store = unlock.id.split(separator: "-").first else { return true }
            return stores.insert(store).inserted
        }
        guard !unlocks.isEmpty else { return }
        pendingNotices += unlocks.map { Notice(news: .unlocked($0)) }
        Task { await showNextNotice() }
    }

    /// Tells `broadcast` in a banner, after any notice already waiting, unless it is already
    /// waiting or on screen; a tap opens its button's place through `open`, as its 通知 row does,
    /// and `shown` hears once it is on screen.
    public func tell(
        _ broadcast: Broadcast, open: @escaping (AppDestination) -> Void, shown: @escaping (Broadcast) -> Void
    ) {
        let news = NoticeNews.broadcast(broadcast)
        guard notice?.news != news, !pendingNotices.contains(where: { $0.news == news }) else { return }
        openDestination = open
        broadcastShown = shown
        pendingNotices.append(Notice(news: news))
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
        // Two in a row, then whatever else waits without a button in one banner.
        if shownInRow >= Self.shownBeforeMore { foldTheRest() }
        let next = pendingNotices.removeFirst()
        shownInRow = pendingNotices.isEmpty ? 0 : shownInRow + 1
        notice = next
        if case .broadcast(let broadcast) = next.news { broadcastShown?(broadcast) }
    }

    /// How many banners drop in one after another before the rest fold into 「还有新通知」.
    static let shownBeforeMore = 2

    /// The banners still to come after the one on screen, for the edges under it.
    var waitingNotices: Int { pendingNotices.count }

    /// Two or more waiting without a button become one 「还有新通知」; those with one keep theirs.
    private func foldTheRest() {
        let plain = pendingNotices.filter { !$0.hasButton && $0.news != .more }
        guard plain.count >= 2 else { return }
        pendingNotices = pendingNotices.filter(\.hasButton) + [Notice(news: .more)]
        // A broadcast folded in is told on this phone too: 通知 has it.
        for case .broadcast(let broadcast) in plain.map(\.news) { broadcastShown?(broadcast) }
    }
}
#endif
