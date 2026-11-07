#if os(iOS)
import AvatarUI
import CheckInDomain
import DesignSystem
import Contracts
import DesignSystemUI
import SportsUI
import SwiftUI

/// My payoff over my character, front and centre: the 「+1」 of a 练了 and the line in the bubble on my head.
struct MyPayoff: View {
    let model: TodayModel
    let openPost: (CheckIn?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / StageLayout.width
            let head = CGPoint(
                x: StageLayout.mySpot.x * unit,
                y: (StageLayout.mySpot.y - Self.headHeight * StageLayout.myScale) * unit)
            // Each piece hangs off a zero-height anchor placed on the head: the bubble and the
            // 「+1」 sit above it, centred.
            ZStack {
                Self.anchor(width: Self.bubbleWidth, at: head, alignment: .bottom) {
                    PayoffBubble(line: model.payoff?.line) { openPost(model.payoff?.post) }.fixedSize(
                        horizontal: false, vertical: true)
                }
                Self.anchor(width: 0, at: CGPoint(x: head.x, y: head.y - Space.l), alignment: .bottom) {
                    PlusOne(trigger: model.celebrations).fixedSize()
                }
            }
        }
    }

    private static func anchor(
        width: Double, at point: CGPoint, alignment: Alignment, @ViewBuilder content: () -> some View
    ) -> some View {
        Color.clear
            .frame(width: width, height: 0)
            .overlay(alignment: alignment, content: content)
            .position(point)
    }

    /// The widest the caption's bubble gets before it wraps.
    private static let bubbleWidth = 240.0

    /// How far above the feet the top of the head is, in the rig's points.
    private static let headHeight = 250.0
}

/// The caption in the character's speech bubble. Nothing until the first post with a line.
struct PayoffBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let line: String?
    let open: () -> Void

    var body: some View {
        if let line {
            SpeechBubble(Text(verbatim: line), kind: .info(title: nil), action: open)
                .transition(.speech(reduceMotion: reduceMotion))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.bubble")
        }
    }
}
#endif
