import Contracts
import DesignSystem
import DesignSystemUI
import FeedUI
import SquadDomain
import SquadUI
import SwiftUI

/// The coach's card, popped up from a tap on the coach on the home (Tracy, 2026-11-05): today's
/// 战术板 over it, as 今天 goes over a teammate's card, and a tap on the 战术板 opens 动态, where it
/// tops today. Before the day's line is written, the card stands alone.
struct CoachCardPopup: View {
    let note: CoachNote?
    let squad: SquadSettingsModel
    /// Puts the card away, opening 动态 when true.
    let close: (_ opensFeed: Bool) -> Void

    var body: some View {
        VStack(spacing: Space.xs) {
            if let note {
                Button {
                    close(true)
                } label: {
                    CoachBoard(note: note, showsCoach: false)
                }
                .buttonStyle(PressableButtonStyle())
                .frame(width: TradingCard.size.width)
                .accessibilityIdentifier("coachCard.board")
            }
            CoachPlayerCard(model: squad) { close(false) }
        }
    }
}
