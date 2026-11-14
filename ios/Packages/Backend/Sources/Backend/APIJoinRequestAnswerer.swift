import Contracts
import DailyPushDomain

/// Answering a request to join from the captain's long-pressed push, over our API: the adapter
/// behind `DailyPushDomain`'s `JoinRequestAnswerer`.
public struct APIJoinRequestAnswerer: JoinRequestAnswerer {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func answer(_ request: JoinRequestID, in squad: SquadID, approve: Bool) async throws(DailyPushError) {
        do {
            try await api.answer(request, in: squad, approve: approve)
        } catch .refused(.squadFull) {
            throw .squadFull
        } catch .refused(.joinRequestClosed) {
            throw .answeredElsewhere
        } catch {
            throw .notSent
        }
    }
}
