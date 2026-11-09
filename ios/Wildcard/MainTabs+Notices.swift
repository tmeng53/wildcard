import CheckInUI
import NotificationsDomain
import SwiftUI

/// What the tabs are told while the app is open. A broadcast (群发通知) or a higher squad goal
/// suggested to the captain, not yet seen in 通知, drops in on 今天 once on this phone, once the
/// home says whose it is. Everything else 通知 is told drops in over whatever page is open
/// (2026-11-08), in place of iOS's banner, above the cards, but not under a screen that covers
/// the tabs, where nobody would see it.
struct TabNotices: ViewModifier {
    let today: TodayModel
    let inbox: NoticeInbox
    /// The editor or a 战报 covers the tabs.
    let covered: Bool
    /// Bumped each time a push arrives while the app is in front, so 通知 reads what it missed.
    let pushesInFront: Int
    /// What decides which broadcasts and goal suggestions are waiting (`bannerNotices`).
    let waiting: [String]
    let tellWaiting: () -> Void
    let tellToldLive: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: waiting, initial: true) { tellWaiting() }
            .todayNotices(today)
            .onChange(of: covered, initial: true) { today.isCovered = $1 }
            .onChange(of: inbox.toldLive) { tellToldLive() }
            .onChange(of: pushesInFront) { Task { await inbox.catchUp() } }
    }
}
