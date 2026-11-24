#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The round gift button under the squad card's trailing end, with its dot, while the coach's gift
/// waits in its box (Tracy, 2026-11-21): it opens the gift's card, and goes once it is opened. At
/// night it stands left of the pull cord, which hangs from the same edge.
struct GiftButton: View {
    let model: TodayModel

    /// From the screen's right edge: the page margin, or past the pull cord while it hangs.
    private var trailing: Double {
        model.phase == .night ? TodayView.cordInset + PullCord.size.width + Space.s : Space.pageMargin
    }

    var body: some View {
        if model.unopenedGift != nil, model.step == .scene {
            HeaderButton(Text(copy: "教练的礼物", bundle: .module), systemImage: "gift", on: .scene) {
                model.openUnopenedGift()
            }
            .newsDot(true)
            .accessibilityIdentifier("today.gift")
            .padding(.trailing, trailing)
            // Hangs under the card: the overlay puts its bottom on the card's, so it moves down by
            // its own height and a gap, as the pull cord does (an offset moves its taps with it).
            .offset(y: Sizing.control + Space.s)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}
#endif
