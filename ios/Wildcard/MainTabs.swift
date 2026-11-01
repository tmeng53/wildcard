import CharacterEditorUI
import CheckInUI
import DesignSystem
import DesignSystemUI
import FeedUI
import MeDomain
import MeUI
import RecapUI
import ScheduleUI
import SquadDomain
import SquadUI
import SwiftUI

/// The app once the member is signed in and in a squad: the four tabs in the system's Liquid Glass
/// tab bar (`AppTabs`). Each tab screen keeps to the safe area, which the system raises above the
/// bar, so none of them draws the bar itself.
struct MainTabs: View {
    enum Tab: Hashable {
        case today, feed, schedule, profile
    }

    let today: TodayModel
    let profile: MeModel
    let schedule: ScheduleModel
    let feed: FeedModel
    let squad: SquadSettingsModel
    let recap: RecapShelf
    @Binding var selection: Tab
    /// The member left the squad on 小队设置.
    var leftSquad: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The character editor, open from 我 over everything.
    @State private var editor: CharacterEditorModel?
    /// 小队设置, open from 我 over everything.
    @State private var showsSquad = false

    var body: some View {
        AppTabs(Self.tabs, selection: $selection, showsBar: showsTabBar) { tab in
            // Only the tab on screen has its screen, made anew on each visit, as every tab expects:
            // a hidden tab kept alive would hold a scroll or a picked day nobody sees.
            if tab == selection { screen(tab) }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: showsTabBar)
        // Read once at the start too, so the 战报 tile is in 动态 before it first opens and a post
        // 今天 opens 动态 on doesn't move down under it.
        .task { await recap.refresh() }
        .fullScreenCover(isPresented: Binding(get: { recap.open != nil }, set: { if !$0 { recap.open = nil } })) {
            if let story = recap.open { RecapView(model: story, autoAdvances: !LaunchOptions.recapManual) }
        }
        // A scene picked on the story's last page: its reveal ends where home takes over.
        .onChange(of: recap.picks) {
            if let picked = recap.picked { land(on: picked.scene, coveredAt: picked.coveredAt) }
        }
        .fullScreenCover(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
            if let editor {
                CharacterEditorView(
                    model: editor, context: .profile, issued: profile.overview?.joinedAt,
                    onBack: { self.editor = nil },
                    onDone: { edited in
                        self.editor = nil
                        Task {
                            await profile.save(
                                MeCharacter(nickname: edited.nickname, outfit: edited.outfit, persona: edited.persona))
                        }
                    })
            }
        }
        .fullScreenCover(isPresented: $showsSquad) {
            SquadSettingsView(
                model: squad, close: { showsSquad = false },
                picked: { scene, coveredAt in
                    // The page goes at once: its reveal's last frame is the scene home draws.
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { showsSquad = false }
                    land(on: scene, coveredAt: coveredAt)
                }
            )
            .environment(\.sceneTheme, squad.scene)
        }
        .onChange(of: squad.hasLeft) { _, left in
            guard left else { return }
            showsSquad = false
            leftSquad()
        }
    }

    /// Every scene pick ends on home: the picked scene filled the screen at `coveredAt`, and the
    /// squad drops onto it.
    private func land(on scene: SceneTheme, coveredAt: Date) {
        selection = .today
        Task { await today.dropIn(on: scene, coveredAt: coveredAt) }
    }

    /// Opens the editor on the member's own character.
    private func editCharacter() {
        guard let character = profile.overview?.character else { return }
        editor = try? CharacterEditorModel.placeholder(
            look: character.outfit, persona: character.persona, nickname: character.nickname)
    }

    /// A tab's full-screen step (writing a check-in, a post's own page, the 注销账号 page) hides the
    /// bar.
    private var showsTabBar: Bool {
        switch selection {
        case .today: today.showsTabBar
        case .profile: !profile.isDeletionOpen
        case .feed: feed.opened == nil
        case .schedule: true
        }
    }

    /// Coming back to 今天 shows the home the store kept at once, then reads the server's again
    /// and sends any post still waiting.
    @ViewBuilder private func screen(_ tab: Tab) -> some View {
        switch tab {
        case .today:
            TodayView(model: today) { post in
                feed.open(post)
                selection = .feed
            }
        case .feed:
            FeedView(model: feed, header: AnyView(RecapTile(recap: recap))) { selection = .today }
                .environment(\.sceneTheme, today.scene)
                .task { await recap.refresh() }
        case .schedule:
            ScheduleView(model: schedule)
                .environment(\.sceneTheme, today.scene)
        case .profile:
            MeView(
                model: profile,
                destinations: MeDestinations(
                    // Past 战报 live in 动态 until they have a page of their own.
                    squad: { showsSquad = true },
                    pastRecaps: { selection = .feed },
                    editCharacter: editCharacter,
                    weeklyTemplate: {
                        schedule.showTemplate()
                        selection = .schedule
                    },
                    privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms)
            )
            .accentTone(.brand)
        }
    }

    /// The tabs as home opens with them, around `content` on 今天, for 上场, whose end hands over
    /// to home: the bar rises once `showsBar`.
    static func entranceTabs(showsBar: Bool, content: AnyView) -> some View {
        AppTabs(tabs, selection: .constant(Tab.today), showsBar: showsBar) { tab in
            if tab == .today { content }
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

/// The squad's newest 战报, once there is one, opening it.
private struct RecapTile: View {
    let recap: RecapShelf

    var body: some View {
        if let story = recap.latest {
            RecapEntryTile(
                week: story.week, pages: story.pages.count, viewer: recap.cast?.reader, action: recap.openLatest)
        }
    }
}
