#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The round gift button under the squad card's trailing end, with its dot, while the coach's gift
/// waits in its box (Tracy, 2026-11-21): it opens the gift's card, and goes once it is opened.
struct GiftButton: View {
    let model: TodayModel

    var body: some View {
        if model.unopenedGift != nil, model.step == .scene {
            HeaderButton(Text(copy: "教练的礼物", bundle: .module), systemImage: "gift", on: .scene) {
                model.openUnopenedGift()
            }
            .newsDot(true)
            .accessibilityIdentifier("today.gift")
            .padding(.trailing, Space.pageMargin)
            .alignmentGuide(.bottom) { $0[.top] - Space.s }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}
#endif
