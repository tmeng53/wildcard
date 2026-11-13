import Contracts
import FeedDomain
import FeedUI
import NotificationsUI
import SwiftUI

/// The one router: every notice, banner, push and broadcast button opens its place here.
extension MainTabs {
    /// Where every notice goes, the one place that decides it: a 通知 row, the home's banners and
    /// a tapped push all open `Notice.destination` here, and a broadcast's button its place. 通知
    /// stays under a post it opens, so back returns to it; elsewhere it closes.
    func open(_ destination: AppDestination) {
        switch destination {
        case .post(let id):
            selection = .feed
            // One post page at a time on 动态: a card's own post makes way.
            feed.opened = nil
            noticePost = OpenedPost(id: id, model: feed.page(of: id))
        case .unlock(let kind, let item):
            // A store or pieces on 商店街, a prop on the editor's 道具, read again first.
            showsNotices = false
            openWardrobe(kind, item: item)
        case .store(let store):
            showsNotices = false
            openWardrobe(.store, item: store)
        case .stores:
            showsNotices = false
            selection = .profile
            closeProfilePages()
            wardrobe.openShop()
        case .trainAlong(let post):
            // 我也发: the member's own 训练, started from the squadmate's, over 今天.
            showsNotices = false
            selection = .today
            todayPages = []
            Task { await today.trainAlong(post) }
        case .wardrobe(let piece):
            showCloset(trying: piece.map { [$0] } ?? [])
        case .place(let place):
            openPlace(place)
        case .badges:
            // 我's player card turned to its badge board.
            showsNotices = false
            selection = .profile
            closeProfilePages()
            wardrobe.badgeMarks.showBoard()
        default:
            showsNotices = false
            openTab(for: destination)
        }
    }

    /// 今天 itself, with today's pats on me again; a morning note opens the coach's page, where
    /// it is one of its cards.
    private func openToday(_ destination: AppDestination) {
        selection = .today
        todayPages = []
        switch destination {
        case .pats: today.replayPatsOnMe()
        case .coachNote, .waitingCoachNote: openCoachDeck()
        case .coachLetter(let letter): today.showAgain(letter)
        case .teamLetter(let broadcast): today.showAgain(broadcast)
        default: break
        }
    }

    /// Whether a 战报 is open over the app.
    var showsStory: Binding<Bool> {
        Binding(get: { recap.open != nil }, set: { if !$0 { recap.open = nil } })
    }

    /// A 战报 closed. After its 排下周, 出赛表 opens on the week after the story's, only now: a
    /// push asked for while the story's cover is still going down is dropped.
    func storyClosed() {
        guard recap.plans != plansOpened, let week = recap.planWeek else { return }
        plansOpened = recap.plans
        schedule.plan(week)
        open(.schedule)
    }

    /// A place that is a tab, or on one: 通知 closes, unless it is the place.
    private func openTab(for destination: AppDestination) {
        switch destination {
        case .feed:
            selection = .feed
        case .recap(let squad, let week):
            // Over 小队, where the story stays in 往期战报 once it closes.
            selection = .today
            todayPages = [.squad]
            Task {
                await recap.refresh()
                await recap.open(week: week, of: squad)
            }
        case .today, .pats, .coachNote, .coachLetter, .waitingCoachNote, .teamLetter:
            openToday(destination)
        case .schedule:
            selection = .profile
            closeProfilePages()
            showsSchedule = true
        case .squad:
            selection = .today
            todayPages = [.squad]
        case .coaches:
            selection = .today
            todayPages = [.coach(.market)]
        case .profile:
            selection = .profile
        case .notices:
            selection = .feed
            showsNotices = true
        case .post, .place, .unlock, .stores, .store, .wardrobe, .badges, .trainAlong:
            break
        }
    }

    /// The tab that wears the bar's dot: 动态, with news since the member last looked.
    var dots: Set<Tab> { feed.hasNews ? [.feed] : [] }

    /// A tab back on its own page, with every page pushed over it closed: the tab left, and the
    /// open one tapped again in the bar (Tracy, 2026-11-06). A scene pick's reveal playing over
    /// 小队 stays until it lands.
    func backToRoot(_ tab: Tab) {
        switch tab {
        case .today:
            if !squadRevealing { todayPages = [] }
        case .feed:
            feed.opened = nil
            feedPages = []
        case .profile:
            closeProfilePages()
        }
    }

    /// 衣橱 in the editor, trying `pieces` on, on the profile read again first unless it is
    /// known to hold them (`readAgain: false`).
    func showCloset(trying pieces: [String], readAgain: Bool = true) {
        showsNotices = false
        selection = .profile
        closeProfilePages()
        if readAgain { Task { await wardrobe.showGift(pieces.first) } } else { wardrobe.tryOn(pieces) }
    }

    /// 我 back on its own page: 设置, 出赛表, 商店街, 我的动态 and a post over it all closed. 设置
    /// stays while an account is being deleted, which can't be left.
    func closeProfilePages() {
        profile.closeDeletion()
        if !profile.isDeletionOpen { showsSettings = false }
        profile.feedbackPage = nil
        showsSchedule = false
        wardrobe.showsShop = false
        wardrobe.editor = nil
        (wall, post, profilePlace, profilePlacePost) = (nil, nil, nil, nil)
    }

    /// 换装 is pushed over 商店街 while the street is open, else over 我; the system's back closes it
    /// without saving.
    func showsEditor(overShop: Bool) -> Binding<Bool> {
        Binding(
            get: { wardrobe.editor != nil && wardrobe.showsShop == overShop },
            set: { if !$0 { wardrobe.editor = nil } })
    }

    @ViewBuilder var profileEditor: some View {
        if let editor = wardrobe.editor {
            ProfileEditor(model: editor, profile: profile, today: today) { wardrobe.editor = nil }
        }
    }

    /// 我 with the wardrobe pushed over it, in place of any other page 我 had open.
    func openWardrobe(_ kind: Unlock.Kind, item: String) {
        selection = .profile
        closeProfilePages()
        Task { await wardrobe.open(kind, item: item) }
    }

    /// A broadcast's button opens what its 通知 row opens; a goal suggestion's opens 小队.
    func tellWaiting() {
        tellBroadcasts()
        tellGoalSuggestions()
    }

    /// The broadcasts not yet seen in 通知 that this phone hasn't shown, each in a banner on 今天.
    func tellBroadcasts() {
        // Whose phone this is shows once the home is in: until then, nothing is told.
        guard let member = today.home?.member.description else { return }
        for broadcast in inbox.unseenBroadcasts where !ShownBroadcasts.contains(broadcast.id, for: member) {
            today.tell(broadcast, open: open) { ShownBroadcasts.mark($0.id, for: member) }
        }
    }

    /// What 通知 was told while the app is open, each in a banner over whatever page is open:
    /// not a comment on the post on screen, which shows it, nor a broadcast or goal suggestion,
    /// which drop in once on each phone (`tellBroadcasts`). An unlock is told by the home, which
    /// knows which it already told; a scene move by the drop onto the new scene.
    func tellToldLive() {
        for notice in inbox.takeToldLive() {
            switch notice.subject {
            case .broadcast, .goalSuggestion:
                continue
            case .unlocked:
                Task { await today.checkUnlocks() }
            case .sceneMoved:
                sceneMoved()
            case .comment(_, let post), .coachReply(let post, _, _, _, _):
                if !isOnScreen(post) { tell(notice) }
            case .dailyProgress, .weeklyAwards, .coachNote, .coachLetter, .trainedWith:
                tell(notice)
            }
        }
    }

    private func tell(_ notice: Notice) {
        today.tell(notice) { AnyView(ToldNoticeBanner($0, unlocked: unlockWords)) }
    }

    /// Whether `post`'s own page is the one on screen.
    private func isOnScreen(_ post: CheckInID) -> Bool {
        switch selection {
        case .feed: if case .post(let opened) = feedPages.last { opened.id == post } else { false }
        case .profile: self.post?.id == post
        case .today: false
        }
    }

    /// A screen over the tabs, which a banner would drop in under.
    var tabsCovered: Bool {
        recap.open != nil || wardrobe.editor != nil
    }

    /// What drops in on 今天 from 通知, with whose phone it is: told again when any changes.
    var bannerNotices: [String] {
        inbox.unseenBroadcasts.map(\.id) + inbox.unseenGoalSuggestions.map(\.id.rawValue.description)
            + [today.home?.member.description ?? ""]
    }

    /// The higher squad goals suggested to the captain not yet seen in 通知 that this phone hasn't
    /// shown, each in a banner on 今天, kept with the broadcasts shown by the notice's id.
    func tellGoalSuggestions() {
        guard let member = today.home?.member.description else { return }
        for notice in inbox.unseenGoalSuggestions {
            let shown = "goalSuggestion-\(notice.id.rawValue)"
            guard case .goalSuggestion(let suggestion) = notice.subject,
                !ShownBroadcasts.contains(shown, for: member)
            else { continue }
            today.tell(suggestion, open: open) { ShownBroadcasts.mark(shown, for: member) }
        }
    }
}

extension MainTabs {
    /// 动态's page of a post opened from 我的动态: an edit or delete there shows on the wall too.
    func postPage(_ id: CheckInID, over wall: PostWallStore) -> FeedModel {
        let page = feed.page(of: id)
        let parent = page.changed
        page.changed = { change in
            parent?(change)
            wall.apply(change)
        }
        return page
    }
}
