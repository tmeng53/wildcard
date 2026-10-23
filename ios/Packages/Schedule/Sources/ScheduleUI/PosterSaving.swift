#if os(iOS)
import DesignSystem
import DesignSystemUI
import Photos
import SwiftUI
import UIKit

/// The poster as a picture: 1080 × 1440, 3:4, the size Xiaohongshu shows a post at.
public typealias PosterImage = UIImage

/// Where 存图 puts the poster. The app passes the photo library; UI tests pass one that only
/// counts, since they can't answer the system's permission prompt.
public protocol PosterSaver: Sendable {
    @MainActor func save(_ image: PosterImage) async -> ScheduleModel.Saving
}

/// Adds the poster to Photos, asking first for permission to add (never to read the library).
public struct PhotoLibrarySaver: PosterSaver {
    public init() {}

    @MainActor public func save(_ image: PosterImage) async -> ScheduleModel.Saving {
        switch await PHPhotoLibrary.requestAuthorization(for: .addOnly) {
        case .authorized, .limited: break
        default: return .notAllowed
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}

/// Says it saved without touching Photos (`-uitest-save-poster`).
public struct PretendPosterSaver: PosterSaver {
    public init() {}

    @MainActor public func save(_ image: PosterImage) async -> ScheduleModel.Saving {
        image.size.width > 0 ? .saved : .failed
    }
}

extension WeekPoster {
    /// How many pixels a poster point is in the saved picture: 360 × 480 points make 1080 × 1440.
    static let savedScale: Double = 3

    /// Draws the poster as the member sees it, without what they have hold of, as a picture.
    /// A renderer starts from a blank environment, so the scene and language come along.
    @MainActor static func picture(of poster: WeekPoster, theme: SceneTheme, locale: Locale) -> PosterImage? {
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
