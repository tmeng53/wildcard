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
                                Text(copy: "第 \(index + 1) 张，共 \(photos.all.count) 张", bundle: .module)
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(Text(copy: "全屏看", bundle: .module))
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
/// the photo fades in over them; a photo that can't be read leaves the plain mist. Decoded off the main actor, so scrolling past photos doesn't drop
/// frames.
private struct FeedPhoto: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let ref: PhotoRef
    @State private var image: CGImage?
    /// The photo couldn't be read, so the tickets stop waiting for it.
    @State private var failed = false

    var body: some View {
        Color(role: .bgSubtle, in: theme)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .transition(.opacity)
                } else if !failed {
                    TicketSpinner(size: 32, on: .light(.bgSubtle))
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .task(id: ref.loadID) {
                failed = false
                guard let jpeg = await model.store.photo(ref), let decoded = await Self.decode(jpeg) else {
                    if !Task.isCancelled { failed = true }
                    return
                }
                withAnimation(.wildcard(Motion.fadeIn)) { image = decoded }
            }
    }

    private nonisolated static func decode(_ jpeg: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}

extension PhotoRef {
    /// What a photo's loading task follows: its path and the URL it is fetched from, since a
    /// refresh signs a new URL for the same path (`PhotoRef`'s equality is the path alone) and a
    /// photo that failed to load should try again with it.
    var loadID: [String?] { [path, viewURL?.absoluteString] }
}
#endif
