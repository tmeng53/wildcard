import Backend
import CheckInDomain
import CheckInUI
import Contracts
import FeedDomain
import FeedUI
import Foundation

extension AppModel {
    /// 动态 on the member's squad, its days by the member's own clock, with what its coach said.
    /// The member's own posts change through 今天's store (`editor`), which recounts.
    static func feed(api: WildcardAPI, home: Home, editor: TodayStore) -> FeedModel {
        let zone = home.timeZone
        let source = APIFeedSource(api: api)
        let store = FeedStore(
            source: source, squad: home.squad.id, viewer: home.member, today: { LocalDay(at: Date(), in: zone) },
            now: { Timestamp(Date()) }, newCommentID: { CommentID(UUID()) })
        let coach = FeedCoach(source: source, squad: home.squad.id) { Date() }
        return FeedModel(store: store, viewer: home.member, editor: editor, coach: coach, now: { Date() })
    }
}
