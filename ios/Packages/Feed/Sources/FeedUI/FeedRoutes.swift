#if os(iOS)
import Contracts

/// Where taps on 动态 open places outside it, which the app sets: a teammate's @ tag opens their
/// card, a post's place tag the place's own page.
public struct FeedRoutes {
    public var openTeammate: (MemberID) -> Void
    public var openPlace: (Place) -> Void

    public init(openTeammate: @escaping (MemberID) -> Void = { _ in }, openPlace: @escaping (Place) -> Void = { _ in })
    {
        (self.openTeammate, self.openPlace) = (openTeammate, openPlace)
    }
}
#endif
