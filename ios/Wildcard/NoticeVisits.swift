import Contracts
import NotificationsDomain
import SwiftUI

/// What a page the member opened is about, so the notices about it are read on every phone (Tracy,
/// 2026-11-14): a teammate's comment read on the post itself never waits in 通知 again.
enum NoticeVisit: Hashable {
    /// A place a notice opens: a post's page, and anywhere `MainTabs.open(_:)` goes.
    case place(AppDestination)
    /// The coach's page, where the morning notes are.
    case coachPage
}

extension EnvironmentValues {
    /// Marks the notices about a page read: the app's inbox while the tabs are up, else nothing.
    @Entry var noticeVisits: (@MainActor (NoticeVisit) -> Void)?
}

extension NoticeInbox {
    /// Marks read every notice about `visit` told by now.
    func visited(_ visit: NoticeVisit) async {
        let now = LaunchOptions.now()
        switch visit {
        case .place(let place):
            await visited(place, at: now)
        case .coachPage:
            await visited(at: now) { notice in
                if case .coachNote = notice.subject { true } else { false }
            }
        }
    }
}

extension View {
    /// Each time this page shows, the notices about `visit` are read.
    func readsNotices(about visit: NoticeVisit) -> some View {
        modifier(ReadsNotices(visit: visit))
    }
}

private struct ReadsNotices: ViewModifier {
    let visit: NoticeVisit
    @Environment(\.noticeVisits) private var visits

    func body(content: Content) -> some View {
        content.onAppear { visits?(visit) }
    }
}
