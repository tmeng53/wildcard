import APIContract
import Contracts
import Foundation
import OpenAPIRuntime

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

    /// Hears the member's live events (`GET /me/events`) until the server ends the stream,
    /// telling `heard` that it is listening and each notice as it is told.
    public func listenForNotices(_ heard: @escaping @Sendable (LiveNotice) async -> Void) async throws(APIError) {
        try await call {
            let events = try await live.streamMyEvents().ok.body.textEventStream
            try await Self.read(events, heard)
        }
    }

    /// The stream's events, in order: `ready`, then `notice`s and `shelf`s; any other event is
    /// skipped.
    static func read(_ events: HTTPBody, _ heard: @Sendable (LiveNotice) async -> Void) async throws {
        for try await event in events.asDecodedServerSentEvents() {
            switch event.event {
            case "ready":
                await heard(.ready)
            case "notice":
                guard let data = event.data?.data(using: .utf8) else { continue }
                let live = try DeviceJSON.decoder.decode(Components.Schemas.LiveNotice.self, from: data)
                await heard(.told(Notice(live.notice)))
            case "shelf":
                await heard(.shelfChanged)
            default:
                continue
            }
        }
    }
}
