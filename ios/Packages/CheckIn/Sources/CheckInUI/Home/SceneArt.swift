#if os(iOS)
import CheckInDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The venue's art, exported from the approved home design (`SceneArt/render.mjs`). The home
/// draws it full screen; 动态's empty state shows a window onto it, and 上场 plays on it.
public struct SceneArt: View {
    public enum Layer: Sendable {
        case day
        /// The dark tint and the lamps, over everything on the scene.
        case night
        /// The lamp tubes alone, flickering on over the lifting dark as the lights come on (开灯).
        case lamps
        /// A part of the venue people stand behind.
        case front(Int)

        var name: String {
            switch self {
            case .day: "day"
            case .night: "night"
            case .lamps: "lamps"
            case .front(let index): "front-\(index)"
            }
        }
    }

    let scene: SceneTheme
    let layer: Layer

    public init(scene: SceneTheme, layer: Layer) {
        self.scene = scene
        self.layer = layer
    }

    /// The art's height on the design's 390-point-wide stage (`StageLayout.width`).
    public static var designHeight: Double { Stage.height }

    public var body: some View {
        Image(uiImage: UIImage(named: "\(scene.rawValue)-\(layer.name)", in: .module, with: nil) ?? UIImage())
            .resizable()
            .accessibilityHidden(true)
    }
}

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
