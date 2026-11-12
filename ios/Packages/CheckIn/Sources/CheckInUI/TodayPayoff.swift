#if os(iOS)
import AvatarUI
import CheckInDomain
import DesignSystem
import Contracts
import DesignSystemUI
import SportsUI
import SwiftUI

/// My payoff over my character, front and centre: the 「+1」 of a 练了 above my head.
struct MyPayoff: View {
    let model: TodayModel

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / StageLayout.width
            let head = CGPoint(
                x: StageLayout.mySpot.x * unit,
                y: (StageLayout.mySpot.y - Self.headHeight * StageLayout.myScale) * unit)
            // It hangs off a zero-size anchor placed above the head, centred.
            Color.clear
                .frame(width: 0, height: 0)
                .overlay(alignment: .bottom) { PlusOne(trigger: model.celebrations).fixedSize() }
                .position(x: head.x, y: head.y - Space.l)
        }
    }

    /// How far above the feet the top of the head is, in the rig's points.
    private static let headHeight = 250.0
}
#endif
