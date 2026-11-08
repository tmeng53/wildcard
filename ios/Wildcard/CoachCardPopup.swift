import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedUI
import SquadDomain
import SquadUI
import SwiftUI

/// The coach's card, popped up from a tap on the coach on the home (Tracy, 2026-11-05): today's
/// 战术板 over it, as 今天 goes over a teammate's card, and a tap on the 战术板 opens 动态, where it
/// tops today. Before the day's line is written, the card stands alone. Once the member put away
/// today's morning note, 今天给你的消息 under the card opens it again (Tracy, 2026-11-07).
struct CoachCardPopup: View {
    /// 今天's model: its 战术板 line, and today's note the member put away (nil hides its row).
    let today: TodayModel
    let squad: SquadSettingsModel
    /// Puts the card away, opening 动态 when true.
    let close: (_ opensFeed: Bool) -> Void

    var body: some View {
        VStack(spacing: Space.xs) {
            if let note = today.coachLine {
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
            if let memberNote = today.todaysNote {
                Button {
                    close(false)
                    today.showAgain(memberNote)
                } label: {
                    HStack(spacing: Space.xxs) {
                        Text(copy: "今天给你的消息", bundle: .main)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .controlPlacement(.floating)
                .accessibilityIdentifier("coachCard.memberNote")
            }
        }
    }
}
