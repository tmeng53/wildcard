import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import FeedUI
import HomeWidgetUI
import LocationDomain
import MeDomain
import MeUI
import NotificationsDomain
import NotificationsUI
import PlacesDomain
import RecapUI
import ScheduleUI
import SquadDomain
import SquadUI
import SwiftUI

/// The app once the member is signed in and in a squad: the three tabs (小队, 动态, 我) in the
/// system's Liquid Glass tab bar (`AppTabs`); the squad's settings open inside 小队 from the
/// home's squad card.
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
    /// What the squad did at a place, for its page.
    let places: any PlaceSource
    /// Squadmates' player cards; nil on the sample squad, whose cards are made from its home.
    let squadmateCards: (any SquadmateCards)?
    @Binding var selection: Tab
    /// A place a tapped push asked for, opened once the tabs are up (`open(_:)`), then cleared.
    @Binding var destination: AppDestination?
    /// The member left the squad on its page.
    var leftSquad: () -> Void = {}
    /// 通知 was told a teammate moved the squad: the app reads the squad's scene again.
    var sceneMoved: () -> Void = {}
    /// Bumped each time a push arrives while the app is in front, which the app tells itself.
    var pushesInFront = 0
    /// 设置 › 管理员's tools, for admins and their demo accounts.
    var admin: AdminTools
    /// 设置 › 位置: the phone's approximate location for the coach's weather.
    let location: LocationSharing?
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
    @State var plansOpened = 0
    /// The pages pushed over 今天: 小队, from the home's squad card, and the coach's pages over it.
    @State var todayPages: [TodayPage] = LaunchOptions.opensSquad ? [.squad] : []
    /// The coach's cards for the member, on its page; made for the squad the page opens on.
    let coachCards: any CoachCardSource
    @State var coachDeck: CoachDeck?
    /// 小队's scene pick is playing its reveal, which fills the screen.
    @State var squadRevealing = false
    /// 我的动态, pushed over 我.
    @State var wall: PostWallStore?
    /// 我的动态's tile on 我: the wall's first page, read again each time 我 shows.
    @State var newestPosts: PostWallStore
    /// A post opened from 我的动态: 动态's post page, pushed over the wall.
    @State var post: OpenedPost?
    /// A place opened from that post's tag, pushed over it.
    @State var profilePlace: Place?
    /// A post opened from that place's tiles, pushed over the place.
    @State var profilePlacePost: OpenedPost?
    /// 设置, pushed over 我.
    @State var showsSettings = false
    /// A player's card, opened from the home or 小队, popped up over every tab and the tab bar.
    @State var teammate: SquadmateCardModel?
    /// The card was opened from the home, so 今天 and 拍一拍 go over it (小队 hides the scene).
    @State private var teammateOnHome = false

    init(
        today: TodayModel, profile: MeModel, schedule: ScheduleModel, feed: FeedModel, squad: SquadSettingsModel,
        recap: RecapShelf, myPosts: any MyPostsSource, places: any PlaceSource, notices: any NoticeSource,
        coachCards: any CoachCardSource,
        squadmateCards: (any SquadmateCards)? = nil, selection: Binding<Tab>,
        destination: Binding<AppDestination?> = .constant(nil), admin: AdminTools = AdminTools(),
        location: LocationSharing? = nil, pushesInFront: Int = 0, sceneMoved: @escaping () -> Void = {},
        leftSquad: @escaping () -> Void = {}
    ) {
        (self.pushesInFront, self.sceneMoved) = (pushesInFront, sceneMoved)
        self.admin = admin
        self.location = location
        (self.today, self.profile, self.schedule, self.feed) = (today, profile, schedule, feed)
        (self.squad, self.recap, self.myPosts, self.places) = (squad, recap, myPosts, places)
        (self.squadmateCards, self.coachCards) = (squadmateCards, coachCards)
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
        // The compose page's place pill pushes the place's page, on 今天 and over a post being edited.
        .environment(\.placePage, composePlacePage)
        // A 练了 that opens a store or prop says so on 今天; a tap opens the editor there.
        .task {
            // 「还有新通知」 and a broadcast's button on 今天 open here too.
            today.openDestination = { open($0) }
            feed.routes = FeedRoutes(
                openTeammate: { (teammateOnHome, teammate) = (false, homeCard(of: $0)) },  // @ tag → card
                openPlace: { open(.place($0)) })
            today.broadcastOpened = { broadcast in Task { await inbox.opened(broadcast) } }
            today.tellUnlocks(
                with: UnlockNotices(
                    banner: { UnlockBanner(unlock: $0) }, open: { open(.unlock($0.kind, item: $0.id)) },
                    badge: { WardrobeBadge($0, item: $1) }, picture: { WardrobePicture($0, item: $1) })
            )
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
        .followsNotices(inbox) { refreshOpenPosts(about: $0) }
        // 商店街 read again when the server says it changed and on each return to the front (a
        // switch's day starting tells nothing), so a store that opened shows without a relaunch.
        .onChange(of: inbox.shelfChanges) { Task { await profile.reload() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await profile.reload() } }
        }
        .placesZones(from: profile, in: today.health)
        .fullScreenCover(isPresented: showsStory, onDismiss: storyClosed) {
            if let story = recap.open { RecapView(model: story, autoAdvances: !LaunchOptions.recapManual) }
        }
        // A scene picked on the story's last page: its reveal ends where home takes over.
        .onChange(of: recap.picks) {
            if let picked = recap.picked { land(on: picked.scene, coveredAt: picked.coveredAt) }
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
        // Every notice told while the app is open, as a banner over any page (`TabNotices`).
        .modifier(
            TabNotices(
                today: today, inbox: inbox, covered: tabsCovered, pushesInFront: pushesInFront,
                waiting: bannerNotices, tellWaiting: tellWaiting,
                tellToldLive: tellToldLive)
        )
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

    /// A tab's full-screen step (writing a check-in, a scene pick's reveal), 通知, and a page pushed
    /// over another pushed page on 我 (a post over 我的动态, 注销账号 over 设置), and any page pushed
    /// over 动态 (通知, a post's page) hide the bar.
    private var showsTabBar: Bool {
        switch selection {
        case .today: todayPages.isEmpty ? today.showsTabBar : !squadRevealing
        // 换装 and 意见反馈 have a button at the foot; their page's own hiding misses the bar.
        case .profile:
            !profile.isDeletionOpen && profile.feedbackPage == nil && post == nil && wardrobe.editor == nil
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
                    // Closing (a delete) takes only this post away: a place or 通知 under it stays.
                    PostDetailView(model: opened.model, post: opened.id) {
                        if case .post(let top) = feedPages.last, top.id == opened.id { feedPages.removeLast() }
                    }
                case .place(let place):
                    placePage(place) { feedPages.append(.post(OpenedPost(id: $0, model: feed.page(of: $0)))) }
                }
            }
        }
        .environment(\.sceneTheme, today.scene)
        .onChange(of: feed.opened) { _, id in pushCardPost(id) }
        // 通知 popped, or 动态 left with it open: what is told from now on lights the bell again.
        .onChange(of: showsNotices) { _, shown in if !shown { inbox.close() } }
        .onDisappear { inbox.close() }
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
            .squadCardNews(squad.waitingRequests > 0)
            .onAppear {
                today.openTeammate = {
                    teammateOnHome = true
                    teammate = homeCard(of: $0)
                }
                opensPagesFromToday()
            }
            .navigationDestination(for: TodayPage.self) { page in
                switch page {
                case .squad:
                    SquadSettingsView(
                        model: squad, picked: land(on:coveredAt:), openCoach: { todayPages.append(.coach($0)) },
                        openPreferences: { todayPages.append(.squadPreferences) },
                        revealing: $squadRevealing,
                        openTeammate: { (teammateOnHome, teammate) = (false, squadCard(of: $0)) },
                        pastRecaps: { PastRecaps(shelf: recap) }
                    )
                    .environment(\.sceneTheme, squad.scene)
                    .task { await recap.refreshPast() }
                case .squadPreferences:
                    SquadPreferencesView(model: squad)
                        .environment(\.sceneTheme, squad.scene)
                case .coach(let route):
                    CoachPage(
                        route: route, model: squad, pages: coachPages, note: today.coachLine,
                        letter: today.coachLetter,
                        swapped: { leaving, coming in
                            // Back on 今天, where they change places while the letter is written.
                            todayPages = []
                            today.handOver(
                                from: CoachSpeaker(id: leaving.id, name: leaving.name),
                                to: CoachSpeaker(id: coming.id, name: coming.name))
                        }
                    )
                    .environment(\.sceneTheme, squad.scene)
                case .coachDeck, .coachEarlier, .coachCard:
                    coachDeckPage(page)
                        .environment(\.sceneTheme, today.scene)
                case .place(let place):
                    placePage(place) { todayPages.append(.post(OpenedPost(id: $0, model: feed.page(of: $0)))) }
                case .post(let opened):
                    PostDetailView(model: opened.model, post: opened.id) { todayPages.removeLast() }
                        .environment(\.sceneTheme, today.scene)
                }
            }
        }
        // 小队 opens on what was read last.
        .task { if squad.load == .loading { await squad.reload() } }
        // A coach hired, changed or fired, from 小队 or the sideline's empty spot, stands there.
        .onChange(of: squad.coach?.coach.id) { Task { await today.reloadCoach() } }
    }
}
