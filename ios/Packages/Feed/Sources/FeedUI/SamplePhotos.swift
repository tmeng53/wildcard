#if os(iOS)
import CheckInUI
import DesignSystem
import DesignSystemUI
import SwiftUI

extension InMemoryFeedSource {
    /// Renders the sample feed's photos as JPEG, by `samplePhotoNames`: a corner of each venue
    /// for the sports, and the dish on the scene's wash for the meals. For previews and UI tests.
    @MainActor public static func renderSamplePhotos() -> [String: Data] {
        var photos: [String: Data] = [:]
        let venues: [String: SceneTheme] = ["track": .track, "pool": .pool, "gym": .gym, "tennis": .tennis]
        for (name, scene) in venues {
            photos[name] = jpeg(of: VenuePhoto(scene: scene))
        }
        photos["salad"] = jpeg(of: DishPhoto(dish: "🥗"))
        photos["burger"] = jpeg(of: DishPhoto(dish: "🍔"))
        return photos
    }

    @MainActor private static func jpeg(of photo: some View) -> Data? {
        let renderer = ImageRenderer(content: photo.frame(width: photoSize.width, height: photoSize.height))
        renderer.scale = 2
        return renderer.uiImage?.jpegData(compressionQuality: 0.8)
    }

    /// A 3:2 photo, as a phone's landscape shot.
    private static let photoSize = CGSize(width: 390, height: 260)
}

/// The venue's art from about where the squad stands.
private struct VenuePhoto: View {
    let scene: SceneTheme

    var body: some View {
        SceneArt(scene: scene, layer: .day)
            .frame(width: 390, height: 844)
            .offset(y: -150)
            .frame(width: 390, height: 260, alignment: .top)
            .clipped()
    }
}

/// A dish on the scene's wash.
private struct DishPhoto: View {
    let dish: String

    var body: some View {
        Color(role: .bgAccentSubtle, in: .track)
            .overlay { Text(verbatim: dish).font(.system(size: 150)) }
    }
}
#endif
