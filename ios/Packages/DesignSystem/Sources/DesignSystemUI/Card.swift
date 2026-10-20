#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Where a card sits, which decides its fill: layers differ by fill, never by shadow or border.
public enum CardSurface: Sendable {
    /// On a white page: a subtle grey block set into it.
    case page
    /// On the scene: solid white, straight on the art.
    case scene
}

extension View {
    /// A card: 16 points of padding, 12-point corners, no border and no shadow.
    public func card(on surface: CardSurface = .page) -> some View {
        modifier(CardBackground(surface: surface))
    }
}

private struct CardBackground: ViewModifier {
    @Environment(\.sceneTheme) private var theme
    let surface: CardSurface

    func body(content: Content) -> some View {
        content
            .padding(Space.cardPadding)
            .background(
                Color(role: surface == .page ? .bgSubtle : .bgCanvas, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
#endif
