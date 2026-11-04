#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The 请假条 a character holds up in front of their chest, wherever it holds one up (the home,
/// 动态), drawn over the figure at the rig's `scale`, centred at y 249 on its canvas.
public struct SignCard: View {
    @Environment(\.sceneTheme) private var theme
    let scale: Double

    public init(scale: Double) { self.scale = scale }

    public var body: some View {
        Text("请假条", bundle: .module)
            .font(.system(size: 27 * scale, weight: .bold))
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .frame(width: 108 * scale, height: 58 * scale)
            .background(Color(role: .bgCanvas, in: theme), in: card)
            .overlay(card.stroke(Color(role: .fgAccent, in: theme), lineWidth: 4 * scale))
    }

    /// The card as the design draws it in the rig's points: 108 by 58, corners of 9.
    private var card: RoundedRectangle {
        RoundedRectangle(cornerSize: CGSize(width: 9 * scale, height: 9 * scale))
    }
}
#endif
