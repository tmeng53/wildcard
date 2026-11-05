import Contracts
import Foundation
import Observation

/// The count on the chat's button beside 打卡: the squad's messages the member hasn't read. Read
/// again when the home shows and when the chat closes; it never fails loudly, it just keeps the
/// last count.
@MainActor @Observable
public final class ChatBadge {
    public private(set) var unread = ChatUnread.none

    private let source: any ChatSource
    public let squad: SquadID

    public init(source: any ChatSource, squad: SquadID) {
        self.source = source
        self.squad = squad
    }

    public func refresh() async {
        do throws(ChatError) {
            unread = try await source.unread(in: squad)
        } catch {
            // The last count stays.
        }
    }
}
