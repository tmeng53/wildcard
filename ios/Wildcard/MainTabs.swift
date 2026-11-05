import CharacterEditorUI
import ChatDomain
import ChatUI
import CheckInDomain
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
/// card (Tracy took 小队's own tab away on 2026-11-04; the coach chat opens from home too).
/// Each tab screen keeps to the safe area, which the system raises above the bar, so none of
/// them draws the bar itself.
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
    /// 群聊 for the member's squad: the API's, or the sample squad's made from its home.
    let chatSource: (Home) -> any ChatSource
    @Binding var selection: Tab
    /// A chat push was tapped: 今天 opens the chat once it can.
    @Binding var opensChat: Bool
    /// The member left the squad on its page.
    var leftSquad: () -> Void = {}
    /// 通知, behind the bell on 动态: one for as long as the tabs are up.
    @State private var inbox: NoticeInbox
    /// 通知's page, open over 动态.
    @State private var showsNotices = false
    /// A post opened from 通知 (the one the coach answered), over its page.
    @State private var noticePost: OpenedPost?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The character editor, open from 我 over everything.
    @State private var editor: CharacterEditorModel?
    /// 出赛表, open from 我 in its place.
    @State private var showsSchedule = LaunchOptions.opensSchedule
    /// 小队, open from the home's squad card in 今天's place.
    @State var showsSquad = LaunchOptions.opensSquad
    /// 小队 opens on its coach's 简历, from a tap on the coach on the home.
    @State private var squadOpensCoach = false
    /// 小队's scene pick is playing its reveal, which fills the screen.
    @State private var squadRevealing = false
    /// 我的动态, open from 我 in its place.
    @State private var wall: PostWallStore?
    /// A post opened from 我的动态: 动态's post page, over the wall.
    @State private var post: OpenedPost?
    /// A player's card, opened from a tap on them on the home or their row on 小队,
    /// popped up over every tab and the tab bar.
    @State private var teammate: SquadmateCardModel?
    /// The card was opened from the home, so 今天 and 拍一拍 go over it; from 小队 the scene isn't
    /// in view to play a pat on.
    @State private var teammateOnHome = false
    /// The count on the chat's button beside 打卡, for the squad on home.
    @State var chatBadge: ChatBadge?
    /// 群聊, open in 今天's place.
    @State var chat: ChatModel?

    init(
        today: TodayModel, profile: MeModel, schedule: ScheduleModel, feed: FeedModel, squad: SquadSettingsModel,
        recap: RecapShelf, myPosts: any MyPostsSource, notices: any NoticeSource,
        squadmateCards: (any SquadmateCards)? = nil, chat: @escaping (Home) -> any ChatSource,
        selection: Binding<Tab>, opensChat: Binding<Bool> = .constant(false), leftSquad: @escaping () -> Void = {}
    ) {
        (self.today, self.profile, self.schedule, self.feed) = (today, profile, schedule, feed)
        (self.squad, self.recap, self.myPosts) = (squad, recap, myPosts)
        self.squadmateCards = squadmateCards
        chatSource = chat
        _selection = selection
        _opensChat = opensChat
        self.leftSquad = leftSquad
        _inbox = State(initialValue: NoticeInbox(source: notices))
    }

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
        .followsNotices(inbox)
        .fullScreenCover(isPresented: Binding(get: { recap.open != nil }, set: { if !$0 { recap.open = nil } })) {
            if let story = recap.open { RecapView(model: story, autoAdvances: !LaunchOptions.recapManual) }
        }
        // A scene picked on the story's last page: its reveal ends where home takes over.
        .onChange(of: recap.picks) {
            if let picked = recap.picked { land(on: picked.scene, coveredAt: picked.coveredAt) }
        }
        .fullScreenCover(isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })) {
            if let editor {
                ProfileEditor(model: editor, profile: profile) { self.editor = nil }
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
            showsSquad = false
            squadOpensCoach = false
            selection = .today
        }
        Task { await today.dropIn(on: scene, coveredAt: coveredAt) }
    }

    /// Opens the editor on the member's own character.
    private func editCharacter() {
        guard let character = profile.overview?.character else { return }
        editor = try? CharacterEditorModel.placeholder(
            look: character.outfit, persona: character.persona, nickname: character.nickname,
            unlocks: profile.overview?.unlocks ?? [], locked: profile.overview?.lockedPieces ?? [])
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
        case .today: chat == nil && (showsSquad ? !squadRevealing : today.showsTabBar)
        case .profile: !profile.isDeletionOpen && post == nil
        case .feed: feed.opened == nil && !showsNotices && noticePost == nil
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

    /// 动态 with the bell at its title, and 通知 over it once the bell is tapped, with a post it
    /// opens over that.
    private var feedPage: some View {
        ZStack {
            FeedView(
                model: feed, header: AnyView(RecapTile(recap: recap)),
                accessory: AnyView(NoticeBell(inbox: inbox) { showsNotices = true })
            ) { selection = .today }
            .allowsHitTesting(!showsNotices)
            .accessibilityHidden(showsNotices)
            .task { await recap.refresh() }
            // The bell's dot, read each time 动态 opens, and the member 通知 shows: their character
            // when it is empty and their unlocks for how a store opened.
            .task {
                await inbox.load()
                if profile.overview == nil { await profile.reload() }
            }
            if showsNotices {
                NoticesView(
                    inbox: inbox, viewer: noticeViewer, unlocked: unlockWords, now: LaunchOptions.now,
                    open: open, close: { showsNotices = false }
                )
                .allowsHitTesting(noticePost == nil)
                .accessibilityHidden(noticePost != nil)
                .transition(.move(edge: .trailing))
            }
            if let noticePost {
                PostDetailView(model: noticePost.model, post: noticePost.id) { self.noticePost = nil }
                    .transition(.move(edge: .trailing))
            }
        }
        .environment(\.sceneTheme, today.scene)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: showsNotices)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: noticePost?.id)
    }

    /// Where a tapped notice goes. 通知 stays under a post or the wardrobe it opens, so back
    /// returns to it; elsewhere it closes.
    private func open(_ target: NoticeTarget) {
        switch target {
        case .feed:
            showsNotices = false
        case .recap(_, let week):
            showsNotices = false
            if recap.latest?.week.monday == week { recap.openLatest() }
        case .home:
            showsNotices = false
            selection = .today
        case .post(let id):
            noticePost = OpenedPost(id: id, model: feed.page(of: id))
        case .wardrobe:
            editCharacter()
        }
    }

    /// The member's own character, on the empty 通知.
    private var noticeViewer: NoticeViewer? {
        profile.overview.map { NoticeViewer(outfit: $0.character.outfit, persona: $0.character.persona) }
    }

    /// A store's, prop's or piece's words and badge on its 通知 row, as the home's banner says them.
    /// How a store or piece opened comes from the member's unlock; a prop's title says it all (the bell design).
    private func unlockWords(_ kind: Unlock.Kind, item: String) -> UnlockWords {
        let unlock = profile.overview?.unlocks.first { $0.kind == kind && $0.id == item }
        return UnlockWords(
            title: UnlockNames.title(kind, item: item),
            detail: kind == .prop ? nil : unlock.map(UnlockNames.detail),
            icon: AnyView(WardrobeBadge(kind, item: item)))
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
                    open: { post = OpenedPost(id: $0.id, model: postPage($0.id, over: wall)) },
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
}

extension MainTabs {
    /// 今天, or 小队 in its place, opened from the home's squad card, or on its coach's 简历 from
    /// a tap on the coach on the sideline.
    private var todayPage: some View {
        ZStack {
            if let chat {
                ChatView(model: chat) {
                    self.chat = nil
                    Task { await chatBadge?.refresh() }
                }
                .environment(\.sceneTheme, today.scene)
                .transition(.move(edge: .trailing))
            } else if showsSquad {
                SquadSettingsView(
                    model: squad, picked: land(on:coveredAt:),
                    close: {
                        showsSquad = false
                        squadOpensCoach = false
                    },
                    revealing: $squadRevealing,
                    openTeammate: {
                        teammateOnHome = false
                        teammate = squadCard(of: $0)
                    },
                    coachNote: today.coachLine, opensCoach: squadOpensCoach
                )
                .environment(\.sceneTheme, squad.scene)
                .transition(.move(edge: .trailing))
            } else {
                TodayView(
                    model: today,
                    openSquad: {
                        squadOpensCoach = false
                        showsSquad = true
                    },
                    openPost: { post in
                        feed.open(post)
                        selection = .feed
                    },
                    besideCheckIn: chatBadge.map { badge in AnyView(ChatEntryButton(badge: badge, open: openChat)) }
                )
                .onAppear {
                    today.openTeammate = {
                        teammateOnHome = true
                        teammate = homeCard(of: $0)
                    }
                    today.openCoach = {
                        squadOpensCoach = true
                        showsSquad = true
                    }
                }
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: showsSquad)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: chat != nil)
        .task(id: today.home?.squad.id) { makeChatBadge() }
        .onChange(of: opensChat, initial: true) { makeChatBadge() }
    }

    /// 动态's page of a post opened from 我的动态: an edit or delete there shows on the wall too.
    private func postPage(_ id: CheckInID, over wall: PostWallStore) -> FeedModel {
        let page = feed.page(of: id)
        let parent = page.changed
        page.changed = { change in
            parent?(change)
            wall.apply(change)
        }
        return page
    }
}

/// A post opened from 我的动态, with the page's own model of it.
private struct OpenedPost {
    let id: CheckInID
    let model: FeedModel
}
