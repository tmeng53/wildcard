#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// What the feed and a post's own page share around their cards: the layer the emoji bar, the
/// grid, who reacted and flying emoji float in, the coordinate space they are placed in, the
/// brand's buttons on the canvas, and the haptics of picking and reacting.
struct FeedSurface: ViewModifier {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    /// False while another surface is over this one (a post's page over the feed): only the top
    /// one places the bar, so the slide picks from the bar the member sees.
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(FeedAnchors.self) { anchors in
                if isActive {
                    FeedLayer(model: model, bar: anchors.bar, who: anchors.who, heads: anchors.heads)
                }
            }
            .coordinateSpace(.named(FeedView.space))
            .background(Color(role: .bgCanvas, in: theme))
            // A brand screen: buttons and selection wear the brand; only the kind tags keep the scene.
            .accentTone(.brand)
            .haptic(.pick, trigger: model.picks)
            .haptic(.appear, trigger: model.lifts)
            .haptic(.reaction, trigger: model.arrivals)
    }
}

extension View {
    func feedSurface(_ model: FeedModel, isActive: Bool = true) -> some View {
        modifier(FeedSurface(model: model, isActive: isActive))
    }
}
#endif
