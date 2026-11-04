#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Where a control sits: inside the page's content (`.inContent`, the default), or floating over
/// it (`.floating`), in a bottom action bar, a header, or over the scene and photos. Buttons that
/// float wear interactive Liquid Glass, as iOS draws a toolbar's; buttons in content stay solid
/// (Tracy, 2026-11-04).
public enum ControlPlacement: Sendable {
    case inContent
    case floating
}

extension EnvironmentValues {
    /// Where the controls inside sit. `actionBar` sets `.floating` for its own content.
    @Entry public var controlPlacement: ControlPlacement = .inContent
}

extension View {
    /// Tells the buttons inside whether they float over the page (glass) or sit in it (solid).
    public func controlPlacement(_ placement: ControlPlacement) -> some View {
        environment(\.controlPlacement, placement)
    }

    /// A page's bottom actions (下一步, 发布, 完成) floating over its content in Liquid Glass: the
    /// system's bottom safe-area bar, so the content scrolls under it behind the scroll edge effect
    /// and stops above it, with no bar of its own. Buttons inside wear glass; the primary one
    /// keeps its tone's colour as a glass tint. With `isShown` false the page has no bar at all, so
    /// no empty strip is kept for it (发动态 while editing a post).
    @ViewBuilder
    public func actionBar<Bar: View>(isShown: Bool = true, @ViewBuilder _ bar: () -> Bar) -> some View {
        if isShown {
            safeAreaBar(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: Space.s) {
                    bar()
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xs)
                .controlPlacement(.floating)
            }
        } else {
            self
        }
    }
}
#endif
