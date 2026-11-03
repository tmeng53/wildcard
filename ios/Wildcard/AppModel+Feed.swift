import Backend
import CheckInDomain
import Contracts
import FeedDomain
import FeedUI
import Foundation

extension AppModel {
    /// 动态 on the member's squad, its days by the member's own clock (the phone's, which the
    /// profile's zone follows once the outbox is empty), with what its coach said.
    static func feed(api: WildcardAPI, home: Home) -> FeedModel {
        let zone = TimeZone.autoupdatingCurrent
        let source = APIFeedSource(api: api)
        let store = FeedStore(
            source: source, squad: home.squad.id, viewer: home.member, today: { LocalDay(at: Date(), in: zone) },
            now: { Timestamp(Date()) }, newCommentID: { CommentID(UUID()) })
        let coach = FeedCoach(source: source, squad: home.squad.id) { Date() }
        return FeedModel(store: store, viewer: home.member, coach: coach, now: { Date() })
    }
}
