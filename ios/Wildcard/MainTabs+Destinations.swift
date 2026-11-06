import Contracts
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
            noticePost = OpenedPost(id: id, model: feed.page(of: id))
        case .unlock(let kind, let item):
            // A store or pieces on 商店街, a prop on the editor's 道具, read again first.
            showsNotices = false
            selection = .profile
            Task { await wardrobe.open(kind, item: item) }
        case .store(let store):
            showsNotices = false
            selection = .profile
            Task { await wardrobe.open(.store, item: store) }
        case .stores:
            showsNotices = false
            selection = .profile
            wardrobe.openShop()
        default:
            showsNotices = false
            openTab(for: destination)
        }
    }

    /// A place that is a tab, or on one: 通知 closes, unless it is the place.
    private func openTab(for destination: AppDestination) {
        switch destination {
        case .feed:
            selection = .feed
        case .recap(_, let week):
            selection = .feed
            Task {
                await recap.refresh()
                if recap.latest?.week.monday == week { recap.openLatest() }
            }
        case .today:
            selection = .today
        case .coachNote(let note):
            selection = .today
            today.showAgain(note)
        case .schedule:
            selection = .profile
            showsSchedule = true
        case .squad:
            selection = .today
            showsSquad = true
        case .profile:
            selection = .profile
        case .notices:
            selection = .feed
            showsNotices = true
        case .post, .unlock, .stores, .store:
            break
        }
    }

    /// The broadcasts not yet seen in 通知 that this phone hasn't shown, each in a banner on 今天.
    func tellBroadcasts() {
        // Whose phone this is shows once the home is in: until then, nothing is told.
        guard let member = today.home?.member.description else { return }
        for broadcast in inbox.unseenBroadcasts where !ShownBroadcasts.contains(broadcast.id, for: member) {
            today.tell(broadcast, open: open) { ShownBroadcasts.mark($0.id, for: member) }
        }
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
