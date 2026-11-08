#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Where a card sits, which decides its look. Never a grey block on a white page (Tracy,
/// 2026-11-08): the brand is white and graphite.
public enum CardSurface: Sendable {
    /// On a white page: white, edged with a hairline.
    case page
    /// On the scene: solid white, straight on the art.
    case scene
}

extension View {
    /// A card: 16 points of padding, 12-point corners, no shadow; on a page, a hairline edge.
    public func card(on surface: CardSurface = .page) -> some View {
        modifier(CardBackground(surface: surface))
    }

    /// A graphite card with white words, like 我's `GlanceTile`s (小队's cards): 16 points of
    /// padding and 12-point corners. What sits on it takes `fgOnBrand` and `fgOnInkMuted`, and
    /// its buttons `SecondaryButtonStyle(.onInk)`, which is white.
    public func inkCard() -> some View {
        modifier(InkCardBackground())
    }
}

private struct InkCardBackground: ViewModifier {
    @Environment(\.sceneTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(Space.cardPadding)
            .background(
                Color(role: .bgBrand, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

private struct CardBackground: ViewModifier {
    @Environment(\.sceneTheme) private var theme
    let surface: CardSurface

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(Space.cardPadding)
            .background(Color(role: .bgCanvas, in: theme), in: shape)
            .overlay {
                if surface == .page {
                    shape.strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                }
            }
    }
}
#endif
