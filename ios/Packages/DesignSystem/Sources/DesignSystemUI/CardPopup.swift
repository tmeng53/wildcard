#if os(iOS)
import DesignSystem
import SwiftUI

extension View {
    /// Pops `card` up in the middle of this view over the ink dimmed to `Scrim.dimOpacity`, for
    /// a card to look at on its own (a teammate's player card): it grows in from a little smaller,
    /// a tap anywhere off it closes it, and it fades with Reduce Motion on. The card brings its
    /// own solid fill; the dim is no glass.
    public func cardPopup<Card: View>(
        isPresented: Binding<Bool>, @ViewBuilder card: @escaping () -> Card
    ) -> some View {
        modifier(CardPopup(isPresented: isPresented, card: card))
    }
}

private struct CardPopup<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    let card: () -> Card
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
