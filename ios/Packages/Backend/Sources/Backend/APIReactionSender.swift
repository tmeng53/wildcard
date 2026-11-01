import Contracts
import DailyPushDomain

/// Reacting from the 6pm push over our API: the adapter behind `DailyPushDomain`'s
/// `ReactionSender`.
public struct APIReactionSender: ReactionSender {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(DailyPushError) {
        do {
            if let emoji {
                try await api.react(emoji, to: checkIn)
            } else {
                try await api.removeReaction(from: checkIn)
            }
        } catch {
            throw .notSent
        }
    }
}
