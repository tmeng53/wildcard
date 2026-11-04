import APIContract
import Contracts
import Foundation

// 通知, the bell on 动态: everything the member was told, and how far they have read.
extension WildcardAPI {
    /// Notices on a page, as the design shows them.
    public static let noticePage = 30

    /// A page of the member's notices, newest first: the newest, or the one older than `before`.
    public func notices(before: NoticeID? = nil) async throws(APIError) -> NoticePage {
        let query = Operations.ListMyNotices.Input.Query(before: before?.rawValue, limit: Self.noticePage)
        return NoticePage(try await call { try await client.listMyNotices(query: query).ok.body.json })
    }

    /// Everything up to `through` is read. Safe to repeat; never goes back.
    public func markNoticesSeen(through: NoticeID) async throws(APIError) {
        _ = try await call { try await client.markMyNoticesSeen(body: .json(through.seen)).ok }
    }
}
