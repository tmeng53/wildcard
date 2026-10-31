#if canImport(SwiftUI)
import AvatarDomain
import SwiftUI

/// One piece of art on its own, such as a store's badge, scaled to fit the view and centred.
public struct ArtworkView: View {
    let width: Double
    let height: Double
    let shapes: [FigureDrawing.DrawableShape]

    public init(_ artwork: Artwork) {
        width = artwork.width
        height = artwork.height
        shapes = FigureDrawing.shapes(artwork.shapes)
    }

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width / width, size.height / height)
            var art = context
            art.transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(
                x: (size.width / scale - width) / 2, y: (size.height / scale - height) / 2)
            art.draw(shapes)
        }
    }
}
#endif
