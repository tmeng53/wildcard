#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI
import UIKit

/// The poster as a picture: 1080 × 1440, 3:4, the size Xiaohongshu shows a post at.
public typealias PosterImage = UIImage

extension SchedulePoster {
    /// How many pixels a poster point is in the saved picture: 360 × 480 points make 1080 × 1440.
    static let savedScale: Double = 3

    /// Draws the poster as the member sees it, without what they have hold of, as a picture.
    /// A renderer starts from a blank environment, so the scene and language come along.
    @MainActor static func picture(of poster: SchedulePoster, theme: SceneTheme, locale: Locale) -> PosterImage? {
        let renderer = ImageRenderer(
            content:
                poster
                .frame(width: size.width, height: size.height)
                .environment(\.sceneTheme, theme)
                .environment(\.locale, locale))
        renderer.scale = savedScale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
#endif
