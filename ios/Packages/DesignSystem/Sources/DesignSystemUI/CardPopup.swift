#if os(iOS)
import DesignSystem
import SwiftUI

extension View {
    /// Pops `card` up in the middle of this view over the ink dimmed to `Scrim.dimOpacity`, for
    /// a card to look at on its own (a teammate's player card), grown to the page's width: it
    /// grows in from a little smaller, a tap anywhere off it closes it, and it fades with Reduce
    /// Motion on. The card brings its own solid fill; the dim is no glass.
    public func cardPopup<Card: View>(
        isPresented: Binding<Bool>, @ViewBuilder card: @escaping () -> Card
    ) -> some View {
        modifier(CardPopup(isPresented: isPresented, card: card))
    }
}

private struct CardPopup<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    let card: () -> Card
    /// The card's own size, before it is grown to the screen.
    @State private var cardSize: CGSize = .zero
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The card grows, text and all, to the width inside the page's gutters (Tracy, 2026-11-12:
    /// the card bigger), and shrinks only where the screen is too short for it.
    private func scale(in space: CGSize) -> Double {
        guard cardSize.width > 0, cardSize.height > 0 else { return 1 }
        let width = (space.width - Space.m * 2) / cardSize.width
        let height = (space.height - Space.m * 2) / cardSize.height
        return min(width, height, Self.largest)
    }

    /// A card on an iPad or a wide window stops growing here.
    private static var largest: Double { 1.4 }

    func body(content: Content) -> some View {
        content.overlay {
            // Read before the dim leaves the safe area, so the card stays centred inside it.
            GeometryReader { proxy in
                ZStack {
                    if isPresented {
                        Color(role: .bgInk, in: theme)
                            .opacity(Scrim.dimOpacity)
                            .contentShape(Rectangle())
                            .onTapGesture { isPresented = false }
                            .accessibilityElement()
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(Text(copy: "关闭", bundle: .module))
                            .accessibilityIdentifier("cardPopup.close")
                            .transition(.opacity)
                        card()
                            .onGeometryChange(for: CGSize.self, of: \.size) { cardSize = $0 }
                            .scaleEffect(scale(in: proxy.size))
                            .padding(proxy.safeAreaInsets)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape) { isPresented = false }
                    }
                }
                // The dim spans the whole window, status bar and tab bar included, so a tap anywhere
                // off the card closes it and nothing under it can be tapped while it is open.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: isPresented)
        }
    }
}
#endif
