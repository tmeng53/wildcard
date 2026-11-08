import Backend
import SquadDomain

extension AppModel {
    /// The coach's cards for the member, on its page, over our API.
    var coachCards: any CoachCardSource { APICoachCardSource(api: api) }
}
