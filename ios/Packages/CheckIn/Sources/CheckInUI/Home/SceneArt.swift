#if os(iOS)
import AvatarArt
import CheckInDomain
import DesignSystem
import DesignSystemUI
import SwiftUI
import Synchronization

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
        Image(uiImage: Self.picture(scene, layer))
            .resizable()
            .accessibilityHidden(true)
    }
}

extension SceneArt {
    /// The picture for `scene` and `layer`: the one an admin put (`scenes/<scene>-<layer>@3x.png`,
    /// downloaded by `Backend`'s `ArtDownloads`), else the one this build ships (the gym's, for a
    /// scene added since). Read from disk once per launch, so a newer download shows from the
    /// next launch.
    static func picture(_ scene: SceneTheme, _ layer: Layer) -> UIImage {
        let name = "\(scene.rawValue)-\(layer.name)"
        if let kept = pictures.withLock({ $0[name] }) { return kept }
        let downloaded = ArtTree.downloadedFile("\(name)@3x.png", in: "scenes")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { UIImage(data: $0, scale: 3) }
        // A scene added since this build, with no picture put yet, stands on the gym's.
        let bundled = UIImage(named: "\(scene.base.rawValue)-\(layer.name)", in: .module, with: nil)
        let picture = downloaded ?? bundled ?? UIImage()
        pictures.withLock { $0[name] = picture }
        return picture
    }

    private static let pictures = Mutex<[String: UIImage]>([:])
}

/// A scene's venue as home draws it, filling the width with nobody on it: what the scene pick's
/// reveal shows as its card rises, before home takes over, and 小队's 本周场地 banner.
public struct SceneBackdrop: View {
    private let scene: SceneTheme
    private let focus: Double

    /// `focus` is how far down the art (0 its top, 1 its foot) sits at the middle of a frame
    /// shorter than the art; the art never leaves a gap above or below.
    public init(scene: SceneTheme, focus: Double = 0) {
        self.scene = scene
        self.focus = focus
    }

    /// Where every scene's venue stands (the wall, the pool, the court, the lanes): a band's
    /// middle, for a frame that shows only a slice of the art.
    public static let venue = 0.4

    public var body: some View {
        GeometryReader { proxy in
            let height = Stage.height * proxy.size.width / StageLayout.width
            let top = min(max(height * focus - proxy.size.height / 2, 0), max(height - proxy.size.height, 0))
            // The art runs past the frame when it is shifted; it takes no taps, so what it covers
            // above (小队's 教练 card over 本周场地) still gets them.
            SceneArt(scene: scene, layer: .day)
                .frame(width: proxy.size.width, height: height)
                .offset(y: -top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .allowsHitTesting(false)
        }
        .background(Color(role: .bgCanvas, in: scene))
    }
}
#endif
