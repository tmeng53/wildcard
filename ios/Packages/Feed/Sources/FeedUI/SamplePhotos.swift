#if os(iOS)
import CheckInUI
import DesignSystem
import DesignSystemUI
import SwiftUI

extension InMemoryFeedSource {
    /// Renders the sample feed's photos as JPEG, at `samplePhotoSizes`: a corner of each venue
    /// for the sports, and the dish on the scene's wash for the meals. For previews and UI tests.
    @MainActor public static func renderSamplePhotos() -> [String: Data] {
        var photos: [String: Data] = [:]
        let venues: [String: SceneTheme] = ["track": .track, "pool": .pool, "gym": .gym, "tennis": .tennis]
        for (name, scene) in venues {
            photos[name] = jpeg(of: VenuePhoto(scene: scene), named: name)
        }
        photos["salad"] = jpeg(of: DishPhoto(dish: "🥗"), named: "salad")
        photos["burger"] = jpeg(of: DishPhoto(dish: "🍔"), named: "burger")
        return photos
    }

    /// The photo at its sample size: 390 points wide, as tall as its shape, drawn at 2x.
    @MainActor private static func jpeg(of photo: some View, named name: String) -> Data? {
        guard let pixels = samplePhotoSizes[name] else { return nil }
        let height = width * Double(pixels.height) / Double(pixels.width)
        let renderer = ImageRenderer(content: photo.frame(width: width, height: height))
        renderer.scale = 2
        return renderer.uiImage?.jpegData(compressionQuality: 0.8)
    }

    private static let width: Double = 390
}

/// The venue's art from about where the squad stands, filling the photo from its top.
private struct VenuePhoto: View {
    let scene: SceneTheme

    var body: some View {
        GeometryReader { photo in
            SceneArt(scene: scene, layer: .day)
                .frame(width: 390, height: 844)
                .offset(y: -150)
                .frame(width: photo.size.width, height: photo.size.height, alignment: .top)
                .clipped()
        }
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
