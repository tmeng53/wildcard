import CharacterEditorUI
import CheckInUI
import DesignSystem
import DesignSystemUI
import MeDomain
import MeUI
import SwiftUI

/// The app once the member is signed in and in a squad: one tab bar over the four tabs. Each tab
/// screen keeps to the safe area, which this raises above the floating bar, so none of them
/// draws or measures the bar itself.
struct MainTabs: View {
    enum Tab: Hashable {
        case today, feed, schedule, profile
    }

    let today: TodayModel
    let profile: MeModel
    @Binding var selection: Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The character editor, open from 我 over everything.
    @State private var editor: CharacterEditorModel?

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
        .fullScreenCover(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
            if let editor {
                CharacterEditorView(
                    model: editor, context: .profile, onBack: { self.editor = nil },
                    onDone: { edited in
                        self.editor = nil
                        Task {
                            await profile.save(
                                MeCharacter(nickname: edited.nickname, outfit: edited.outfit, persona: edited.persona))
                        }
                    })
            }
        }
    }

    /// Opens the editor on the member's own character.
    private func editCharacter() {
        guard let character = profile.overview?.character else { return }
        editor = try? CharacterEditorModel.placeholder(
            look: character.outfit, persona: character.persona, nickname: character.nickname)
    }

    /// A tab's full-screen step (writing a check-in, the 注销账号 page) covers the bar.
    private var showsTabBar: Bool {
        switch selection {
        case .today: today.showsTabBar
        case .profile: !profile.isDeletionOpen
        case .feed, .schedule: true
        }
    }

    /// Coming back to 今天 shows the home the store kept at once, then reads the server's again
    /// and sends any post still waiting.
    @ViewBuilder private var screen: some View {
        switch selection {
        case .today:
            TodayView(model: today) { selection = .feed }
        case .feed:
            UpcomingTab(title: Text("动态"))
        case .schedule:
            UpcomingTab(title: Text("出赛表"))
        case .profile:
            MeView(
                model: profile,
                destinations: MeDestinations(
                    // The squad lives on 今天 and past 战报 in 动态 until each has a page of its own.
                    squad: { selection = .today },
                    pastRecaps: { selection = .feed },
                    editCharacter: editCharacter,
                    privacyPolicy: nil, terms: nil))
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
