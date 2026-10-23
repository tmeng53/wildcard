#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A scene's venue as home draws it, filling the screen with nobody on it: what the scene pick's
/// reveal shows as its card rises, before home takes over.
public struct SceneBackdrop: View {
    private let scene: SceneTheme

    public init(scene: SceneTheme) {
        self.scene = scene
    }

    public var body: some View {
        GeometryReader { proxy in
            SceneArt(scene: scene, layer: .day)
                .frame(width: proxy.size.width, height: Stage.height * proxy.size.width / StageLayout.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Color(role: .bgCanvas, in: scene))
    }
}
#endif
