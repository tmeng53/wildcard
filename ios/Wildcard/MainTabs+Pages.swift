import Contracts
import DesignSystemUI
import FeedUI
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
        TabBarItem(id: .today, title: Text("今天"), systemImage: "sun.max", accessibilityIdentifier: "tab.today"),
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
}

/// A post opened from 我的动态 or 通知, with the page's own model of it; one post is one page.
struct OpenedPost: Hashable {
    let id: CheckInID
    let model: FeedModel

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
