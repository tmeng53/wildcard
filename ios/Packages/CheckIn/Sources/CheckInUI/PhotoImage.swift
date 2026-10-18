#if os(iOS)
import DesignSystem
import DesignSystemUI
import ImageIO
import SwiftUI

/// A prepared photo, filling its frame. Decoded once per view; prepared photos are small.
struct PhotoImage: View {
    @Environment(\.sceneTheme) private var theme
    let photo: PreparedPhoto
    @State private var image: Image?

    var body: some View {
        Color(role: .divider, in: theme)
            .overlay {
                if let image {
                    image.resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: photo.id) { image = Self.decode(photo) }
    }

    private static func decode(_ photo: PreparedPhoto) -> Image? {
        guard let source = CGImageSourceCreateWithData(photo.jpeg as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
#endif
