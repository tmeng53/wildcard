#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import Foundation
import SwiftUI

/// News, in a `NoticeBanner` at the top of whatever page is open (2026-11-08): a teammate moving
/// the squad to another scene, a store or prop the member's training unlocked, a notice we sent
/// every member (群发通知), and whatever else 通知 is told while the app is open (a comment, the
/// coach's reply, the 战报), in place of iOS's banner.
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
        /// The squad trained over its goal weeks in a row: the captain is suggested a higher one,
        /// told on this phone once; its button opens 小队.
        case goalSuggestion(GoalSuggestion)
        /// Posts the server refused while they went out late (`TodayModel.failed`, read when it is
        /// drawn, so one banner always says how many); its button, when `canResend`, opens the
        /// oldest to change and send again.
        case sendFailed(canResend: Bool)
        /// What waited after two in a row, in one banner that opens 通知 (approved C, 2026-11-05).
        case more
        /// A notice told while the app was open, in its 通知 words; its button opens what its row
        /// opens.
        case told(Contracts.Notice)
    }

    /// One notice on the home.
    struct Notice: Identifiable, Equatable {
        let news: NoticeNews
        /// New for each notice, so the same news told twice drops in again.
        let id = UUID()

        /// A broadcast's button never folds into 「还有新通知」, so it can still be tapped on 今天;
        /// nor does a celebration, which is its own card, nor a refused post, which 通知 doesn't
        /// keep: it stays until it is tapped or swiped away.
        var hasButton: Bool {
            switch news {
            case .broadcast(let broadcast):
                broadcast.action != nil || broadcast.style == .celebration || broadcast.letter != nil
            case .goalSuggestion: true
            case .sendFailed: true
            case .moved, .unlocked, .more, .told: false
            }
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

    /// 通知 was told of an unlock while the app is open: reads which the home hasn't told yet, and
    /// tells them.
    public func checkUnlocks() async {
        await store.checkUnlocks()
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

    /// The posts the server refused while they went out late, in one banner that replaces any
    /// told before: 重发 opens the oldest to change and send again. A 请假条 has no page to open,
    /// so it is only told.
    func tellRefused() {
        let refused = store.takeRefused().map(\.pending)
        guard !refused.isEmpty else { return }
        failed += refused
        announceFailed()
    }

    /// 重发: the oldest refused post that can be edited opens on the compose page with everything
    /// it had; the rest are told again once the home is free. A 请假条 was told with it and goes.
    func resendFirst() {
        guard let index = failed.firstIndex(where: { $0.draft.kind != .disclaimer }) else { return }
        let post = failed.remove(at: index)
        failed.removeAll { $0.draft.kind == .disclaimer }
        resend(post)
        if !failed.isEmpty { announceFailed() }
    }

    private func announceFailed() {
        let news = NoticeNews.sendFailed(canResend: failed.contains { $0.draft.kind != .disclaimer })
        pendingNotices.removeAll { if case .sendFailed = $0.news { true } else { false } }
        if case .sendFailed = notice?.news {
            // Already on screen: it says the new count by itself; only its button may change.
            if notice?.news != news { notice = Notice(news: news) }
            return
        }
        pendingNotices.append(Notice(news: news))
        Task { await showNextNotice() }
    }

    /// Tells `broadcast` in a banner, after any notice already waiting, unless it is already
    /// waiting or on screen; a tap opens its button's place through `open`, as its 通知 row does,
    /// and `shown` hears once it is on screen.
    public func tell(
        _ broadcast: Broadcast, open: @escaping (AppDestination) -> Void, shown: @escaping (Broadcast) -> Void
    ) {
        let news = NoticeNews.broadcast(broadcast)
        guard notice?.news != news, celebration != broadcast, teamLetter?.broadcast != broadcast,
            !pendingNotices.contains(where: { $0.news == news })
        else { return }
        openDestination = open
        let next = Notice(news: news)
        bannerShown[next.id] = { shown(broadcast) }
        pendingNotices.append(next)
        Task { await showNextNotice() }
    }

    /// Tells the captain `suggestion` in a banner, after any notice already waiting, unless it is
    /// already waiting or on screen; a tap opens 小队 through `open`, as its 通知 row does, and
    /// `shown` hears once it is on screen.
    public func tell(
        _ suggestion: GoalSuggestion, open: @escaping (AppDestination) -> Void, shown: @escaping () -> Void
    ) {
        let news = NoticeNews.goalSuggestion(suggestion)
        guard notice?.news != news, !pendingNotices.contains(where: { $0.news == news }) else { return }
        openDestination = open
        let next = Notice(news: news)
        bannerShown[next.id] = shown
        pendingNotices.append(next)
        Task { await showNextNotice() }
    }

    /// Tells `notice`, which 通知 was just told while the app is open, in a banner after any
    /// already waiting; nothing without `toldBanner` to draw it.
    public func tell(_ notice: Contracts.Notice, banner: @escaping (Contracts.Notice) -> AnyView) {
        toldBanner = banner
        let news = NoticeNews.told(notice)
        guard self.notice?.news != news, !pendingNotices.contains(where: { $0.news == news }) else { return }
        pendingNotices.append(Notice(news: news))
        Task { await showNextNotice() }
    }

    /// How long `notice` stays: one with a button stays until it is tapped or swiped away.
    func hold(_ notice: Notice) -> Double? {
        notice.hasButton ? nil : noticeHold
    }

    /// The next notice waiting, once the squad has landed: not while a check-in is being written
    /// or the burst is open, when it waits for the next load. A celebration waits for 今天, and
    /// the banners after it go first.
    func showNextNotice() async {
        await untilArrived()
        guard isFreeForNotices, pendingNotices.contains(where: canShowNow) else { return }
        // Two in a row, then whatever else waits without a button in one banner.
        if shownInRow >= Self.shownBeforeMore { foldTheRest() }
        guard let index = pendingNotices.firstIndex(where: canShowNow) else { return }
        let next = pendingNotices.remove(at: index)
        shownInRow = pendingNotices.isEmpty ? 0 : shownInRow + 1
        if case .broadcast(let broadcast) = next.news, broadcast.letter != nil {
            teamLetter = ShownTeamLetter(broadcast: broadcast, isSealed: true, shownAt: now())
        } else if case .broadcast(let broadcast) = next.news, broadcast.style == .celebration {
            celebration = broadcast
        } else {
            notice = next
        }
        bannerShown.removeValue(forKey: next.id)?()
    }

    /// Whether the next notice can be told: nothing told is on screen, and no check-in, burst,
    /// opening or screen over the tabs is in front.
    var isFreeForNotices: Bool {
        notice == nil && celebration == nil && teamLetter == nil && opening == nil && step == .scene && !isBurstOpen
            && !isCovered
    }

    /// A celebration is a card on 今天's scene, and a letter flies in over it; every other notice
    /// drops in over any page.
    private func canShowNow(_ waiting: Notice) -> Bool {
        guard case .broadcast(let broadcast) = waiting.news, broadcast.style == .celebration || broadcast.letter != nil
        else { return true }
        return isHomeInFront
    }

    /// The member answered the celebration's card: its button (`opening`) opens its place and
    /// reads its 通知 row, as the banner's does; 先不了, or a tap off the card, just puts it away.
    /// The next notice follows once the home is free again (`todayNotices`), so a place it opened
    /// is never covered.
    public func closeCelebration(opening: Bool) {
        guard let shown = celebration else { return }
        celebration = nil
        if opening, let action = shown.action {
            broadcastOpened?(shown)
            openDestination?(action.destination)
        }
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
        for folded in plain { bannerShown.removeValue(forKey: folded.id)?() }
    }
}
#endif
