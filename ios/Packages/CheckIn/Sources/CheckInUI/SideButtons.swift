#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The round buttons hanging under the squad card's trailing end, one column. 教练有话说, while
/// the squad has a coach, opens its page as a tap on the coach does, with a dot while the page
/// has a card not seen (Tracy, 2026-11-24). Under it, the gift button, while the coach's gift
/// waits in its box (Tracy, 2026-11-21): it opens the gift's card, and goes once it is opened. At
/// night they stand left of the pull cord, which hangs from the same edge.
struct SideButtons: View {
    let model: TodayModel

    /// From the screen's right edge: the page margin, or past the pull cord while it hangs.
    private var trailing: Double {
        model.phase == .night ? TodayView.cordInset + PullCord.size.width + Space.s : Space.pageMargin
    }

    private var showsCoach: Bool { model.sidelineCoach != nil }
    private var showsGift: Bool { model.unopenedGift != nil }

    /// How many buttons the column holds.
    private var count: Int { (showsCoach ? 1 : 0) + (showsGift ? 1 : 0) }

    var body: some View {
        if model.step == .scene, count > 0 {
            column
                .padding(.trailing, trailing)
                // Hangs under the card: the overlay puts the column's bottom on the card's, so it
                // moves down by its own height and a gap, as the pull cord does (an offset moves
                // its taps with it). An alignment guide isn't read through this view.
                .offset(y: Double(count) * Sizing.control + Double(count) * Space.s)
        }
    }

    private var column: some View {
        VStack(spacing: Space.s) {
            if showsCoach {
                HeaderButton(Text(copy: "教练有话说", bundle: .module), systemImage: "megaphone", on: .scene) {
                    model.tapCoach()
                }
                .newsDot(model.coachHasNews)
                .accessibilityValue(model.coachHasNews ? Text(copy: "有新消息", bundle: .module) : Text(verbatim: ""))
                .accessibilityIdentifier("today.coachNews")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if showsGift {
                HeaderButton(Text(copy: "教练的礼物", bundle: .module), systemImage: "gift", on: .scene) {
                    model.openUnopenedGift()
                }
                .newsDot(true)
                .accessibilityIdentifier("today.gift")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }
}
#endif
