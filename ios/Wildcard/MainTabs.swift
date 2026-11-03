import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
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
        case today, feed, squad, profile
    }

    let today: TodayModel
    let profile: MeModel
    let schedule: ScheduleModel
    let feed: FeedModel
    let squad: SquadSettingsModel
    let recap: RecapShelf
    /// The member's own posts, for 我的动态.
    let myPosts: any MyPostsSource
    @Binding var selection: Tab
    /// The member left the squad on 小队.
    var leftSquad: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The character editor, open from 我 over everything.
    @State private var editor: CharacterEditorModel?
    /// 出赛表, open from 我 in its place.
    @State private var showsSchedule = LaunchOptions.opensSchedule
    /// 小队's scene pick is playing its reveal, which fills the screen.
    @State private var squadRevealing = false
    /// 我的动态, open from 我 in its place.
    @State private var wall: PostWallStore?
    /// A post opened from 我的动态: 动态's post page, over the wall.
    @State private var post: OpenedPost?

    var body: some View {
        AppTabs(Self.tabs, selection: $selection, showsBar: showsTabBar, dotted: feed.hasNews ? [.feed] : []) { tab in
            // Only the tab on screen has its screen, made anew on each visit, as every tab expects:
            // a hidden tab kept alive would hold a scroll or a picked day nobody sees.
            if tab == selection { screen(tab) }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: showsTabBar)
        // A 练了 that opens a store or prop says so on 今天; a tap opens the editor there.
        .task { today.tellUnlocks(with: UnlockNotices(banner: { UnlockBanner(unlock: $0) }, open: openUnlock)) }
        // Read once at the start too, so the 战报 tile is in 动态 before it first opens and a post
        // 今天 opens 动态 on doesn't move down under it.
        .task { await recap.refresh() }
        // 动态's dot: looked for each minute while 动态 isn't open; opening it clears the dot.
        .task(id: selection) {
            while selection != .feed, !Task.isCancelled {
                await feed.checkNews()
                try? await Task.sleep(for: .seconds(60))
            }
        }
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
        .onChange(of: squad.hasLeft) { _, left in
            guard left else { return }
            leftSquad()
        }
    }

    /// Every scene pick ends on home: the picked scene filled the screen at `coveredAt`, and the
    /// squad drops onto it.
    private func land(on scene: SceneTheme, coveredAt: Date) {
        // At once: the reveal's last frame is the scene home draws.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            squadRevealing = false
            selection = .today
        }
        Task { await today.dropIn(on: scene, coveredAt: coveredAt) }
    }

    /// Opens the editor on the member's own character.
    private func editCharacter() {
        guard let character = profile.overview?.character else { return }
        editor = try? CharacterEditorModel.placeholder(
            look: character.outfit, persona: character.persona, nickname: character.nickname,
            unlocks: profile.overview?.unlocks ?? [])
    }

    /// A tap on the home's notice that a store or prop opened: 我's editor, inside that store or on
    /// the props, read again first so what just opened is open in it.
    private func openUnlock(_ unlock: Unlock) {
        selection = .profile
        Task {
            await profile.reload()
            editCharacter()
            editor?.show(unlock)
        }
    }

    /// A tab's full-screen step (writing a check-in, a post's own page, the 注销账号 page, a scene
    /// pick's reveal) hides the bar.
    private var showsTabBar: Bool {
        switch selection {
        case .today: today.showsTabBar
        case .profile: !profile.isDeletionOpen && post == nil
        case .feed: feed.opened == nil
        case .squad: !squadRevealing
        }
    }

    /// Coming back to 今天 shows the home the store kept at once, then reads the server's again
    /// and sends any post still waiting.
    @ViewBuilder private func screen(_ tab: Tab) -> some View {
        switch tab {
        case .today:
            TodayView(
                model: today, openSquad: { selection = .squad },
                openPost: { post in
                    feed.open(post)
                    selection = .feed
                })
        case .feed:
            FeedView(model: feed, header: AnyView(RecapTile(recap: recap))) { selection = .today }
                .environment(\.sceneTheme, today.scene)
                .task { await recap.refresh() }
        case .squad:
            SquadSettingsView(
                model: squad, picked: land(on:coveredAt:),
                // Past 战报 live in 动态 until they have a page of their own.
                pastRecaps: { selection = .feed }, revealing: $squadRevealing
            )
            .environment(\.sceneTheme, squad.scene)
        case .profile:
            profilePage
        }
    }

    /// 我, or 出赛表 or 我的动态 in its place, with a post opened from the wall over it.
    private var profilePage: some View {
        ZStack {
            if showsSchedule {
                ScheduleView(model: schedule) { showsSchedule = false }
                    .environment(\.sceneTheme, today.scene)
                    // Its buttons keep the scene's colour, as its poster does; 我's own are brand.
                    .accentTone(.scene)
                    .transition(.move(edge: .trailing))
            } else if let wall {
                PostWallView(
                    store: wall, back: { self.wall = nil },
                    open: { post = OpenedPost(id: $0.id, model: feed.page(of: $0.id)) },
                    checkIn: { selection = .today }
                )
                .allowsHitTesting(post == nil)
                .accessibilityHidden(post != nil)
                .transition(.move(edge: .trailing))
                if let post {
                    PostDetailView(model: post.model, post: post.id) { self.post = nil }
                        .environment(\.sceneTheme, today.scene)
                        .transition(.move(edge: .trailing))
                }
            } else {
                MeView(
                    model: profile,
                    destinations: MeDestinations(
                        editCharacter: editCharacter,
                        schedule: { showsSchedule = true },
                        myPosts: { wall = PostWallStore(source: myPosts) },
                        privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms)
                )
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: wall != nil)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: showsSchedule)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: post?.id)
        .accentTone(.brand)
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
            id: .squad, title: Text("小队"), systemImage: "person.3", accessibilityIdentifier: "tab.squad"),
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
                story: story, viewer: recap.cast?.reader, seen: recap.latestIsSeen, action: recap.openLatest)
        }
    }
}

/// A post opened from 我的动态, with the page's own model of it.
private struct OpenedPost {
    let id: CheckInID
    let model: FeedModel
}
