#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import ImageIO
import SwiftUI

/// A post's photos across the top of its card, swiped one to the next, the cover first. A double
/// tap pops a big ❤️ where it landed, which flies to the author's character (never taking a
/// reaction back).
struct PostPhotos: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let post: FeedPost
    let photos: Photos

    static let height: Double = 236

    var body: some View {
        TabView {
            ForEach(Array(photos.all.enumerated()), id: \.element) { index, ref in
                FeedPhoto(model: model, ref: ref)
                    .accessibilityLabel(
                        Text("第 \(index + 1) 张，共 \(photos.all.count) 张", bundle: .module))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.all.count > 1 ? .always : .never))
        .frame(height: Self.height)
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
        )
        .onTapGesture(count: 2, coordinateSpace: .named(FeedView.space)) { location in
            guard post.canRespond(model.viewer) else { return }
            model.react(.doubleTap, on: post, from: location)
        }
        .accessibilityElement(children: .contain)
    }
}

/// One photo, filling its page: its place in grey until it loads. Decoded off the main actor, so
/// scrolling past photos doesn't drop frames.
private struct FeedPhoto: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let ref: PhotoRef
    @State private var image: CGImage?

    var body: some View {
        Color(role: .borderDefault, in: theme)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: ref) {
                guard let jpeg = await model.store.photo(ref) else { return }
                image = await Self.decode(jpeg)
            }
    }

    private nonisolated static func decode(_ jpeg: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
#endif
