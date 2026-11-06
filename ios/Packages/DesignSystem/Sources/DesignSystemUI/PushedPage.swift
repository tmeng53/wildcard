#if os(iOS)
import DesignSystem
import SwiftUI

// Pages that open over another (小队, 设置, 商店街, a post's page…) are pushed on the system's
// NavigationStack, so going back is iOS's own: the back button pinned in the glass bar, and a
// swipe right from anywhere on the page (iOS 26) that tracks the finger, keeps the page under it
// in view, and settles with the finger's speed (提议 6, approved 2026-11-04; Tracy asked again on
// 2026-11-05 for the swipe to feel like other apps'). Nothing here draws or animates a page.

extension View {
    /// The root of a NavigationStack: it draws its own header, so the stack shows no bar over it.
    public func navigationRoot() -> some View {
        toolbarVisibility(.hidden, for: .navigationBar)
    }

    /// A page pushed on a NavigationStack: the system's back button, a chevron only, in the glass
    /// bar. `canGoBack` false takes the button and the swipe away while a change can't be left
    /// (deleting the account). `hidesTabBar` puts the tab bar away while the page is up, as it
    /// slides in, for a page with its own bottom bar (a post's comment box).
    public func pushedPage(canGoBack: Bool = true, hidesTabBar: Bool = false) -> some View {
        navigationBarTitleDisplayMode(.inline)
            // On iPhone the editor role shows the back button without the last page's title.
            .toolbarRole(.editor)
            .navigationBarBackButtonHidden(!canGoBack)
            .toolbarVisibility(hidesTabBar ? .hidden : .automatic, for: .tabBar)
    }

    /// On a pushed page's scroll view: once its own heading has scrolled up under the bar, the
    /// heading shows small in the bar, as iOS's large titles do.
    public func barTitleOnScroll(_ title: Text) -> some View {
        modifier(BarTitleOnScroll(title: title))
    }
}

private struct BarTitleOnScroll: ViewModifier {
    let title: Text
    @State private var isShown = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the page scrolls before its heading is under the bar: about one heading's height.
    private static let headingHeight = 48.0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Self.headingHeight
            } action: { _, past in
                isShown = past
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    title
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                        .opacity(isShown ? 1 : 0)
                        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: isShown)
                        // The page's own heading is the one VoiceOver reads.
                        .accessibilityHidden(true)
                }
            }
    }
}
#endif
