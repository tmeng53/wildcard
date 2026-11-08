import CharacterEditorUI
import Contracts
import DesignSystemUI
import FeedUI
import MeDomain
import NotificationsUI
import RecapUI
import SquadUI
import SwiftUI

// What MainTabs' tabs show and push.

extension MainTabs {
    /// The tabs as home opens with them, around `content` on 今天, for 上场, whose end hands over
    /// to home: the bar rises once `showsBar`.
    static func entranceTabs(showsBar: Bool, content: AnyView) -> some View {
        AppTabs(tabs, selection: .constant(Tab.today), showsBar: showsBar) { tab in
            if tab == .today { content }
        }
    }

    static let tabs: [TabBarItem<Tab>] = [
        TabBarItem(id: .today, title: Text("小队"), systemImage: "sun.max", accessibilityIdentifier: "tab.today"),
        TabBarItem(
            id: .feed, title: Text("动态"), systemImage: "bubble.left.and.bubble.right",
            accessibilityIdentifier: "tab.feed"
        ),
        TabBarItem(
            id: .profile, title: Text("我"), systemImage: "person.crop.circle", accessibilityIdentifier: "tab.me"),
    ]
}

/// The squad's newest 战报, once there is one, opening it.
struct RecapTile: View {
    let recap: RecapShelf

    var body: some View {
        if let story = recap.latest {
            RecapEntryTile(
                story: story, viewer: recap.cast?.reader, seen: recap.latestIsSeen, action: recap.openLatest)
        }
    }
}

/// A page pushed over 今天.
enum TodayPage: Hashable {
    case squad
    case coach(CoachRoute)
    /// The coach's own page, from a tap on the coach on 今天: its cards for the member.
    case coachDeck
    /// 以前, from the clock on the coach's page.
    case coachEarlier
    /// A card opened from 以前.
    case coachCard(CoachPageCard)
}

/// A post opened from 动态's card (with the feed's model), 我的动态 or 通知 (with the page's own
/// model of it); one post is one page.
struct OpenedPost: Hashable {
    let id: CheckInID
    let model: FeedModel

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A page pushed over 动态.
enum FeedPage: Hashable {
    /// 通知, behind the bell.
    case notices
    /// A post's page: a card's, straight over 动态, or one a notice opened, over 通知 or straight
    /// over 动态.
    case post(OpenedPost)
}

extension MainTabs {
    /// 通知 is pushed over 动态; closing it takes any post over it away too.
    var showsNotices: Bool {
        get { feedPages.first == .notices }
        nonmutating set { feedPages = newValue ? [.notices] : [] }
    }

    /// The member's own character, on the empty 通知.
    var noticeViewer: NoticeViewer? {
        profile.overview.map { NoticeViewer(outfit: $0.character.outfit, persona: $0.character.persona) }
    }

    /// A card's comments open its post's page, pushed straight over 动态 on the same path.
    func pushCardPost(_ id: CheckInID?) {
        guard let id else { return }
        let page = FeedPage.post(OpenedPost(id: id, model: feed))
        if feedPages != [page] { feedPages = [page] }
    }

    /// The post a notice opened, over 通知 when it is open, so back returns to it.
    var noticePost: OpenedPost? {
        get {
            guard case .post(let opened) = feedPages.last else { return nil }
            return opened
        }
        nonmutating set {
            let under: [FeedPage] = showsNotices ? [.notices] : []
            feedPages = under + (newValue.map { [.post($0)] } ?? [])
        }
    }

    /// A store's, prop's or piece's words and badge on its 通知 row, as the home's banner says them.
    /// How a store or piece opened comes from the member's unlock; a prop's title says it all (the bell design).
    func unlockWords(_ kind: Unlock.Kind, item: String) -> UnlockWords {
        let unlock = profile.overview?.unlocks.first { $0.kind == kind && $0.id == item }
        return UnlockWords(
            title: UnlockNames.title(kind, item: item),
            detail: kind == .prop ? nil : unlock.map(UnlockNames.detail),
            icon: AnyView(WardrobeBadge(kind, item: item)))
    }
}

extension MainTabs {
    /// The coach's pages on 今天's stack; taking them away goes back to the page under them (小队,
    /// the coach's own page, or 今天 when they opened from the sideline's empty spot).
    var coachPages: Binding<[CoachRoute]> {
        Binding(
            get: {
                todayPages.compactMap { page -> CoachRoute? in
                    guard case .coach(let route) = page else { return nil }
                    return route
                }
            },
            set: { routes in
                let under = todayPages.prefix { page in
                    if case .coach = page { return false }
                    return true
                }
                todayPages = Array(under) + routes.map(TodayPage.coach)
            })
    }
}
