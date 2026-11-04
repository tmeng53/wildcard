import Contracts
import NotificationsDomain

/// The API's 通知, as the bell and its page read them.
public struct APINoticeSource: NoticeSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func notices(before: NoticeID?) async throws(NotificationsError) -> NoticePage {
        do { return try await api.notices(before: before) } catch { throw Self.reason(error) }
    }

    public func markSeen(through: NoticeID) async throws(NotificationsError) {
        do { try await api.markNoticesSeen(through: through) } catch { throw Self.reason(error) }
    }

    public func listen(_ heard: @escaping @Sendable (LiveNotice) async -> Void) async throws(NotificationsError) {
        do { try await api.listenForNotices(heard) } catch { throw Self.reason(error) }
    }

    /// Only a session that is over means something to 通知; anything else is tried again on the
    /// next load.
    private static func reason(_ error: APIError) -> NotificationsError {
        error == .account(.signedOut) ? .signedOut : .unavailable
    }
}
