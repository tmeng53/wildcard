#if os(iOS)
import DesignSystemUI
import SwiftUI

extension SquadCard {
    /// The home's squad card: a ring in its 今天 row opens that member's card (Tracy, 2026-11-10),
    /// and today's challenge row shows who set it, whose head opens its card on the coach's page,
    /// and 我完成了.
    func onHome(_ model: TodayModel) -> Self {
        opensMember { model.tapRing($0.id) }
            .challenge(complete: model.completeChallenge, open: model.openMyChallenge) {
                ChallengeCoachHead(model.myChallenge?.coach)
            }
    }
}
#endif
