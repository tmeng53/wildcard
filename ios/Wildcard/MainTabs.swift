import CheckInUI
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The app once the member is signed in and in a squad: one tab bar over the four tabs. Each tab
/// screen keeps to the safe area, which this raises above the floating bar, so none of them
/// draws or measures the bar itself.
struct MainTabs: View {
    enum Tab: Hashable {
        case today, feed, schedule, profile
    }

    let today: TodayModel
    @Binding var selection: Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            // The bar floats `tabBarBottom` above the screen's edge, inside the home indicator's
            // inset; screens leave room for it and a little air.
            let room = Sizing.tabBarBottom + Sizing.tabBar + Space.xs - proxy.safeAreaInsets.bottom
            screen
                .safeAreaPadding(.bottom, showsTabBar ? max(room, 0) : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if showsTabBar {
                        TabBar(Self.tabs, selection: $selection)
                            .padding(.horizontal, Space.pageMargin)
                            .offset(y: proxy.safeAreaInsets.bottom - Sizing.tabBarBottom)
                            .transition(.opacity)
                    }
                }
                .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: showsTabBar)
        }
    }

    /// A tab's full-screen step (writing a check-in) covers the bar.
    private var showsTabBar: Bool {
        selection != .today || today.showsTabBar
    }

    /// Coming back to 今天 shows the home the store kept at once, then reads the server's again
    /// and sends any post still waiting.
    @ViewBuilder private var screen: some View {
        switch selection {
        case .today:
            TodayView(model: today)
        case .feed:
            UpcomingTab(title: Text("动态"))
        case .schedule:
            UpcomingTab(title: Text("出赛表"))
        case .profile:
            UpcomingTab(title: Text("我"))
        }
    }

    private static let tabs: [TabBarItem<Tab>] = [
        TabBarItem(id: .today, title: Text("今天"), systemImage: "sun.max", accessibilityIdentifier: "tab.today"),
        TabBarItem(
            id: .feed, title: Text("动态"), systemImage: "bubble.left.and.bubble.right",
            accessibilityIdentifier: "tab.feed"
        ),
        TabBarItem(
            id: .schedule, title: Text("出赛表"), systemImage: "calendar",
            accessibilityIdentifier: "tab.schedule"),
        TabBarItem(
            id: .profile, title: Text("我"), systemImage: "person.crop.circle", accessibilityIdentifier: "tab.me"),
    ]
}

/// A tab whose screen is still being built: its name on a white page.
private struct UpcomingTab: View {
    let title: Text
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        title
            .typeStyle(TypeRamp.largeTitle)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.l)
            .background(Color(role: .bgCanvas, in: theme))
            .accessibilityIdentifier("tab.upcoming")
    }
}
