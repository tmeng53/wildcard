#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The stock every trading card is printed on, like a baseball card: a member's player card and
/// the coach's card. Ink, rounded, at 300 × 460 points, or the width it is given at those
/// proportions; inside, the character stands in a light grey window (`TradingCard.window`).
public enum TradingCard {
    public static let size = CGSize(width: 300, height: 460)
    /// The card's outline.
    public static let shape = RoundedRectangle(cornerRadius: Radius.card + Space.xxs, style: .continuous)
    /// The character's window on the front.
    public static let window = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
}

extension View {
    /// A side of a trading card: this content inset on the ink stock, at the card's size, or
    /// across the width it is given at the card's proportions when `fillsWidth`.
    public func tradingCardStock(fillsWidth: Bool = false) -> some View {
        modifier(TradingCardStock(fillsWidth: fillsWidth))
    }
}

private struct TradingCardStock: ViewModifier {
    let fillsWidth: Bool
    @Environment(\.sceneTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(Space.xs)
            .frame(
                width: fillsWidth ? nil : TradingCard.size.width, height: fillsWidth ? nil : TradingCard.size.height
            )
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .aspectRatio(TradingCard.size.width / TradingCard.size.height, contentMode: .fit)
            .background(Color(role: .bgInk, in: theme), in: TradingCard.shape)
            .contentShape(TradingCard.shape)
    }
}
#endif
