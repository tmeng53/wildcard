#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import ImageIO
import SwiftUI

/// A post's photos across the top of its card, swiped one to the next, the cover first, in a
/// box of the cover's shape (`PhotoFrame`: portrait up to 4:5). A tap opens them full screen;
/// a double tap pops a big ❤️ where it landed, which flies to the author's character (never
/// taking a reaction back).
struct PostPhotos: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let post: FeedPost
    let photos: Photos
    @State private var page = 0
    @State private var isViewing = false

    var body: some View {
        Color.clear
            .aspectRatio(PhotoFrame.aspectRatio(of: photos), contentMode: .fit)
            .overlay {
                TabView(selection: $page) {
                    ForEach(Array(photos.all.enumerated()), id: \.element) { index, ref in
                        FeedPhoto(model: model, ref: ref)
                            .accessibilityLabel(
                                Text("第 \(index + 1) 张，共 \(photos.all.count) 张", bundle: .module)
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(Text("全屏看", bundle: .module))
                            .accessibilityAction { isViewing = true }
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.all.count > 1 ? .always : .never))
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
            )
            .onTapGesture(count: 2, coordinateSpace: .named(FeedView.space)) { location in
                guard post.canRespond(model.viewer) else { return }
                model.react(.doubleTap, on: post, from: location)
            }
            .onTapGesture { isViewing = true }
            .photoViewer(isPresented: $isViewing, count: photos.all.count, page: $page) { [model, photos] index in
                await model.store.photo(photos.all[index])
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.photos")
    }
}

/// One photo, filling its page: until it loads, the two tickets rock small on the card's mist, and
/// the photo fades in over them. Decoded off the main actor, so scrolling past photos doesn't drop
/// frames.
private struct FeedPhoto: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let ref: PhotoRef
    @State private var image: CGImage?

    var body: some View {
        Color(role: .bgSubtle, in: theme)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .transition(.opacity)
                } else {
                    TicketSpinner(size: 32, on: .light(.bgSubtle))
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .task(id: ref) {
                guard let jpeg = await model.store.photo(ref) else { return }
                let decoded = await Self.decode(jpeg)
                withAnimation(.wildcard(Motion.fadeIn)) { image = decoded }
            }
    }

    private nonisolated static func decode(_ jpeg: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
#endif
