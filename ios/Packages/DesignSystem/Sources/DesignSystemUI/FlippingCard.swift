#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A trading card that a tap turns over, front to back and back again, with 轻点翻面 under it: a
/// member's player card and the coach's card. The front is one button; the back may hold buttons
/// of its own, so a tap anywhere else on it turns it over. With Reduce Motion on, the sides swap
/// with a fade.
public struct FlippingCard<Front: View, Back: View>: View {
    private let hint: ColorRole?
    private let fillsWidth: Bool
    private let identifier: String
    private let front: Front
    private let back: Back
    @State private var showsBack = false
    /// How far the card has turned on its vertical axis, in degrees: it turns edge-on, swaps sides
    /// out of sight and turns back.
    @State private var turn: Double = 0
    @State private var isTurning = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - hint: the colour of the 轻点翻面 line under the card: muted on a page, on-ink over a
    ///     dim; nil leaves the line out.
    ///   - fillsWidth: spans the width it is given at the page proportions, instead of its own size.
    ///   - identifier: the front's accessibility identifier; the back's is it with `Back`.
    public init(
        hint: ColorRole? = .fgMuted, fillsWidth: Bool = false, identifier: String,
        @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back
    ) {
        (self.hint, self.fillsWidth, self.identifier) = (hint, fillsWidth, identifier)
        (self.front, self.back) = (front(), back())
    }

    public var body: some View {
        VStack(spacing: Space.s) {
            Group {
                if showsBack {
                    back.tradingCardStock(fillsWidth: fillsWidth)
                        .onTapGesture(perform: flip)
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(named: Text("轻点翻面", bundle: .module), flip)
                        .accessibilityIdentifier(identifier + "Back")
                } else {
                    Button(action: flip) { front.tradingCardStock(fillsWidth: fillsWidth) }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityHint(Text("轻点翻面", bundle: .module))
                        .accessibilityIdentifier(identifier)
                }
            }
            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            // It turns over rather than swipes, so it says so.
            if let hint {
                Text("轻点翻面", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: hint, in: theme))
                    .accessibilityHidden(true)
            }
        }
    }

    /// Half a turn each way on the page spring's time.
    private func flip() {
        guard !isTurning else { return }
        if reduceMotion {
            withAnimation(.wildcard(Motion.page, reduceMotion: true)) { showsBack.toggle() }
            return
        }
        isTurning = true
        let half = Motion.page.response / 2
        withAnimation(.easeIn(duration: half)) {
            turn = 90
        } completion: {
            showsBack.toggle()
            turn = -90
            withAnimation(.easeOut(duration: half)) {
                turn = 0
            } completion: {
                isTurning = false
            }
        }
    }
}
#endif
