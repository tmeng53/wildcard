import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import FeedUI
import MeDomain
import MeUI
import NotificationsDomain
import NotificationsUI
import RecapUI
import ScheduleUI
import SquadDomain
import SquadUI
import SwiftUI

/// The app once the member is signed in and in a squad: the three tabs (今天, 动态, 我) in the
/// system's Liquid Glass tab bar (`AppTabs`), with 小队 opened inside 今天 from the home's squad
/// card (Tracy took 小队's own tab away on 2026-11-04).
/// Each tab screen keeps to the safe area, which the system raises above the bar, so none of
/// them draws the bar itself. Each tab is a NavigationStack: every page that opens over a tab's
/// screen is pushed on it, so going back (the back button, a swipe right) is the system's.
struct MainTabs: View {
    enum Tab: Hashable {
        case today, feed, profile
    }

    let today: TodayModel
    let profile: MeModel
    let schedule: ScheduleModel
    let feed: FeedModel
    let squad: SquadSettingsModel
    let recap: RecapShelf
    /// The member's own posts, for 我的动态.
    let myPosts: any MyPostsSource
    /// Squadmates' player cards; nil on the sample squad, whose cards are made from its home.
    let squadmateCards: (any SquadmateCards)?
    @Binding var selection: Tab
    /// A place a tapped push asked for, opened once the tabs are up (`open(_:)`), then cleared.
    @Binding var destination: AppDestination?
    /// The member left the squad on its page.
    var leftSquad: () -> Void = {}
    /// 设置's 预览注册, for admins; nil for everyone else.
    var previewSignUp: (() -> Void)?
    /// 通知, behind the bell on 动态: one for as long as the tabs are up.
    @State var inbox: NoticeInbox
    /// The pages pushed over 动态: 通知, once the bell is tapped, and a post a notice opens, over
    /// 通知 or straight over 动态 (the home's banner, a push).
    @State var feedPages: [FeedPage] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// 商店街 and the character editor, open from 我.
    @State var wardrobe: Wardrobe
    /// 出赛表, pushed over 我.
    @State var showsSchedule = LaunchOptions.opensSchedule
    /// The pages pushed over 今天: 小队, from the home's squad card, and the coach's pages over it.
    @State var todayPages: [TodayPage] = LaunchOptions.opensSquad ? [.squad] : []
    /// The coach's card, opened from a tap on the coach on the home, popped up like a player's.
    @State var showsCoachCard = false
    /// 小队's scene pick is playing its reveal, which fills the screen.
    @State var squadRevealing = false
    /// 我的动态, pushed over 我.
    @State var wall: PostWallStore?
    /// 我的动态's tile on 我: the wall's first page, read again each time 我 shows.
    @State private var newestPosts: PostWallStore
    /// A post opened from 我的动态: 动态's post page, pushed over the wall.
    @State var post: OpenedPost?
    /// 设置, pushed over 我.
    @State var showsSettings = false
    /// A player's card, opened from the home or 小队, popped up over every tab and the tab bar.
    @State var teammate: SquadmateCardModel?
    /// The card was opened from the home, so 今天 and 拍一拍 go over it (小队 hides the scene).
    @State private var teammateOnHome = false

    init(
        today: TodayModel, profile: MeModel, schedule: ScheduleModel, feed: FeedModel, squad: SquadSettingsModel,
        recap: RecapShelf, myPosts: any MyPostsSource, notices: any NoticeSource,
        squadmateCards: (any SquadmateCards)? = nil, selection: Binding<Tab>,
        destination: Binding<AppDestination?> = .constant(nil), previewSignUp: (() -> Void)? = nil,
        leftSquad: @escaping () -> Void = {}
    ) {
        self.previewSignUp = previewSignUp
        (self.today, self.profile, self.schedule, self.feed) = (today, profile, schedule, feed)
        (self.squad, self.recap, self.myPosts) = (squad, recap, myPosts)
        self.squadmateCards = squadmateCards
        _selection = selection
        _destination = destination
        self.leftSquad = leftSquad
        _inbox = State(initialValue: NoticeInbox(source: notices))
        _newestPosts = State(initialValue: PostWallStore(source: myPosts))
        _wardrobe = State(initialValue: Wardrobe(profile: profile) { today.home?.member.description })
    }

    var body: some View {
        AppTabs(Self.tabs, selection: $selection, showsBar: showsTabBar, dotted: dots, backToRoot: backToRoot) { tab in
            // Only the tab on screen has its screen, made anew on each visit, as every tab expects:
            // a hidden tab kept alive would hold a scroll or a picked day nobody sees.
            if tab == selection { screen(tab) }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: showsTabBar)
        // A 练了 that opens a store or prop says so on 今天; a tap opens the editor there.
        .task {
            // 「还有新通知」 and a broadcast's button on 今天 open here too.
            today.openDestination = { open($0) }
            today.broadcastOpened = { broadcast in Task { await inbox.opened(broadcast) } }
            today.tellUnlocks(
                with: UnlockNotices(
                    banner: { UnlockBanner(unlock: $0) }, open: { open(.unlock($0.kind, item: $0.id)) },
                    badge: { WardrobeBadge($0, item: $1) }, picture: { WardrobePicture($0, item: $1) })
            )
        }
        // A broadcast (群发通知) not yet seen in 通知 drops in on 今天 once on this phone, once the
        // home says whose it is; its button opens what its 通知 row opens.
        // So does a higher squad goal suggested to the captain, whose button opens 小队.
        .onChange(of: bannerNotices, initial: true) {
            tellBroadcasts()
            tellGoalSuggestions()
        }
        // A tapped push's place.
        .onChange(of: destination, initial: true) { _, asked in
            guard let asked else { return }
            destination = nil
            open(asked)
        }
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
        .followsNotices(inbox)
        // 商店街 read again when the server says it changed and on each return to the front (a
        // switch's day starting tells nothing), so a store that opened shows without a relaunch.
        .onChange(of: inbox.shelfChanges) { Task { await profile.reload() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await profile.reload() } }
        }
        .fullScreenCover(isPresented: Binding(get: { recap.open != nil }, set: { if !$0 { recap.open = nil } })) {
            if let story = recap.open { RecapView(model: story, autoAdvances: !LaunchOptions.recapManual) }
        }
        // A scene picked on the story's last page: its reveal ends where home takes over.
        .onChange(of: recap.picks) {
            if let picked = recap.picked { land(on: picked.scene, coveredAt: picked.coveredAt) }
        }
        .fullScreenCover(
            isPresented: Binding(get: { wardrobe.editor != nil }, set: { if !$0 { wardrobe.editor = nil } })
        ) {
            if let editor = wardrobe.editor {
                ProfileEditor(model: editor, profile: profile) { wardrobe.editor = nil }
            }
        }
        .cardPopup(isPresented: Binding(get: { teammate != nil }, set: { if !$0 { teammate = nil } })) {
            if let teammate {
                // What they're up to today over their card, with 拍一拍 (2026-11-04).
                VStack(spacing: Space.xs) {
                    if teammateOnHome {
                        MateTodayStrip(model: today, member: teammate.member) { self.teammate = nil }
                            .frame(width: SquadmateCardPopup.width)
                    }
                    TeammateCard(model: teammate)
                }
                .environment(\.sceneTheme, today.scene)
            }
        }
        // A celebration broadcast (「感恩节快到了」) over everything, told only while 今天 is in front.
        .celebrationPopup(today)
        .onChange(of: homeInFront, initial: true) { today.isHomeInFront = $1 }
        .cardPopup(isPresented: $showsCoachCard) {
            CoachCardPopup(today: today, squad: squad, close: closeCoachCard, browse: browseCoaches)
                .environment(\.sceneTheme, today.scene)
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
            todayPages = []
            selection = .today
        }
        Task { await today.dropIn(on: scene, coveredAt: coveredAt) }
    }

    /// 我 with the wardrobe pushed over it, in place of any other page 我 had open.
    func openWardrobe(_ kind: Unlock.Kind, item: String) {
        selection = .profile
        closeProfilePages()
        Task { await wardrobe.open(kind, item: item) }
    }

    /// A tab's full-screen step (writing a check-in, a scene pick's reveal), 通知, and a page pushed
    /// over another pushed page on 我 (a post over 我的动态, 注销账号 over 设置), and any page pushed
    /// over 动态 (通知, a post's page) hide the bar.
    private var showsTabBar: Bool {
        switch selection {
        case .today: todayPages.isEmpty ? today.showsTabBar : !squadRevealing
        case .profile: !profile.isDeletionOpen && post == nil
        case .feed: feedPages.isEmpty
        }
    }

    /// Coming back to 今天 shows the home the store kept at once, then reads the server's again
    /// and sends any post still waiting.
    @ViewBuilder private func screen(_ tab: Tab) -> some View {
        switch tab {
        case .today:
            todayPage
        case .feed:
            feedPage
        case .profile:
            profilePage
        }
    }

    /// 动态 with the bell at its title: a card's post page, or 通知 once the bell is tapped with a
    /// post it opens over that, pushed on its one path.
    private var feedPage: some View {
        NavigationStack(path: $feedPages) {
            FeedView(
                model: feed, header: AnyView(RecapTile(recap: recap)),
                accessory: AnyView(NoticeBell(inbox: inbox) { showsNotices = true })
            ) { selection = .today }
            .navigationRoot()
            .task { await recap.refresh() }
            // The bell's dot, read each time 动态 opens, and the member 通知 shows: their character
            // when it is empty and their unlocks for how a store opened.
            .task {
                await inbox.load()
                if profile.overview == nil { await profile.reload() }
            }
            .navigationDestination(for: FeedPage.self) { page in
                switch page {
                case .notices:
                    NoticesView(
                        inbox: inbox, viewer: noticeViewer, unlocked: unlockWords, now: LaunchOptions.now, open: open
                    )
                case .post(let opened):
                    PostDetailView(model: opened.model, post: opened.id) { noticePost = nil }
                }
            }
        }
        .environment(\.sceneTheme, today.scene)
        .onChange(of: feed.opened) { _, id in pushCardPost(id) }
        // 通知 popped, or 动态 left with it open: what is told from now on lights the bell again.
        .onChange(of: showsNotices) { _, shown in if !shown { inbox.close() } }
        .onDisappear { inbox.close() }
    }

    /// 我, with 出赛表, 商店街 or 我的动态 pushed over it, and a post opened from the wall or from
    /// 训练记录 pushed over that; closing the post reads 我 again, as an edit or a delete there may
    /// change the record.
    private var profilePage: some View {
        NavigationStack {
            MeView(
                model: profile,
                destinations: MeDestinations(
                    editCharacter: wardrobe.editCharacter,
                    schedule: { showsSchedule = true },
                    street: wardrobe.openShop, streetHasNews: wardrobe.hasNews,
                    openPost: { post = OpenedPost(id: $0, model: feed.page(of: $0)) },
                    privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms,
                    previewSignUp: previewSignUp, health: today.health),
                isSettingsOpen: $showsSettings
            ) {
                MyPostsTile(store: newestPosts) { wall = PostWallStore(source: myPosts) }
            }
            .navigationRoot()
            .navigationDestination(isPresented: $showsSchedule) {
                ScheduleView(model: schedule)
                    .environment(\.sceneTheme, today.scene)
                    // Its buttons keep the scene's colour, as its poster does; 我's own are brand.
                    .accentTone(.scene)
            }
            .navigationDestination(isPresented: showsShop) {
                if let shop = wardrobe.shop { ShoppingStreetPage(model: shop) }
            }
            .navigationDestination(isPresented: showsWall) {
                if let wall {
                    PostWallView(
                        store: wall,
                        open: { post = OpenedPost(id: $0.id, model: postPage($0.id, over: wall)) },
                        checkIn: { selection = .today }
                    )
                    .navigationDestination(item: $post) { opened in
                        PostDetailView(model: opened.model, post: opened.id) { post = nil }
                            .environment(\.sceneTheme, today.scene)
                    }
                }
            }
            // A post from 训练记录 is pushed straight over 我.
            .navigationDestination(item: recordPost) { opened in
                PostDetailView(model: opened.model, post: opened.id) { post = nil }
                    .environment(\.sceneTheme, today.scene)
            }
        }
        .onChange(of: post?.id) { _, id in if id == nil { Task { await profile.reload() } } }
        // 商店街 follows what 我 reads, made again only while it is closed so an open one keeps its place.
        .task(id: wardrobe.key) { wardrobe.refresh() }
        .accentTone(.brand)
    }

    /// 我的动态 is pushed; the system's back closes it.
    private var showsWall: Binding<Bool> {
        Binding(
            get: { wall != nil },
            set: {
                guard !$0 else { return }
                (wall, post) = (nil, nil)
            })
    }

    /// 商店街 is pushed; the system's back closes it.
    private var showsShop: Binding<Bool> {
        Binding(
            get: { wardrobe.showsShop && wardrobe.shop != nil },
            set: { if !$0 { wardrobe.showsShop = false } })
    }

    /// A post opened from 训练记录, pushed over 我 while 我的动态 isn't open; the system's back
    /// closes it.
    private var recordPost: Binding<OpenedPost?> {
        Binding(get: { wall == nil ? post : nil }, set: { if $0 == nil { post = nil } })
    }
}

extension MainTabs {
    /// 今天, with 小队 pushed over it from the home's squad card and the coach's pages over that.
    private var todayPage: some View {
        NavigationStack(path: $todayPages) {
            TodayView(
                model: today,
                openSquad: { todayPages = [.squad] },
                openPost: { post in
                    // 动态 opens on the post itself, not on 通知 left open there.
                    feedPages = []
                    feed.open(post)
                    selection = .feed
                }
            )
            .navigationRoot()
            .onAppear {
                today.openTeammate = {
                    teammateOnHome = true
                    teammate = homeCard(of: $0)
                }
                today.openCoach = { showsCoachCard = true }
            }
            .navigationDestination(for: TodayPage.self) { page in
                switch page {
                case .squad:
                    SquadSettingsView(
                        model: squad, picked: land(on:coveredAt:),
                        openCoach: { todayPages.append(.coach($0)) },
                        revealing: $squadRevealing,
                        openTeammate: {
                            teammateOnHome = false
                            teammate = squadCard(of: $0)
                        }
                    )
                    .environment(\.sceneTheme, squad.scene)
                case .coach(let route):
                    CoachPage(route: route, model: squad, pages: coachPages, note: today.coachLine)
                        .environment(\.sceneTheme, squad.scene)
                }
            }
        }
        // 小队 opens on what was read last.
        .task { if squad.load == .loading { await squad.reload() } }
        // A coach hired, changed or fired, from 小队 or the sideline's empty spot, stands there.
        .onChange(of: squad.coach?.coach.id) { Task { await today.reloadCoach() } }
    }
}
