#if os(iOS)
import DesignSystem
import DesignSystemUI
import ImageIO
import SwiftUI

/// A prepared photo, filling its frame. Decoded once per view, off the main actor, so a
/// transition carrying photos doesn't drop frames.
struct PhotoImage: View {
    @Environment(\.sceneTheme) private var theme
    let photo: PreparedPhoto
    @State private var image: CGImage?

    var body: some View {
        Color(role: .divider, in: theme)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: photo.id) { image = await Self.decode(photo) }
    }

    /// Decodes now rather than on first draw, which would land on the main actor.
    private nonisolated static func decode(_ photo: PreparedPhoto) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(photo.jpeg as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
#endif
