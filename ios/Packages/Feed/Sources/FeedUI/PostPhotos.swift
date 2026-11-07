#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import ImageIO
import SportsUI
import SwiftUI

/// A post's cover across the top of its card: its photos and, for a 训练 from Health, the map or
/// chart in the member's order, swiped one to the next with dots, the first being the cover. The
/// box takes the photos' shape (`PhotoFrame`: portrait up to 4:5), or the map's or chart's own
/// without photos. A tap on a photo opens the photos full screen; a double tap anywhere pops a
/// big ❤️ where it landed, which flies to the author's character (never taking a reaction back).
struct PostPhotos: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let post: FeedPost
    let tiles: [Contracts.PostTile]
    @State private var page = 0
    @State private var isViewing = false
    /// The photo the viewer shows, which follows the page it opened on.
    @State private var photoPage = 0

    private var photoRefs: [PhotoRef] {
        tiles.compactMap { if case .photo(let ref) = $0 { ref } else { nil } }
    }

    private var workout: Workout? {
        if case .trained(let training) = post.checkIn.entry { training.workout } else { nil }
    }

    private var activity: Activity {
        if case .trained(let training) = post.checkIn.entry { training.activity } else { .sport("run") }
    }

    /// The photos' shape; a map alone is a little taller than a chart alone.
    private var aspectRatio: Double {
        if let photos = try? Photos(photoRefs) { return PhotoFrame.aspectRatio(of: photos) }
        return tiles.first == .workout(.map) ? Self.mapAspect : Self.chartAspect
    }

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                TabView(selection: $page) {
                    ForEach(Array(tiles.enumerated()), id: \.element) { index, tile in
                        face(tile)
                            .accessibilityLabel(label(tile, index: index))
                            .accessibilityAddTraits(isPhoto(tile) ? .isButton : [])
                            .accessibilityHint(isPhoto(tile) ? Text(copy: "全屏看", bundle: .module) : Text(verbatim: ""))
                            .accessibilityAction { open(index) }
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: tiles.count > 1 ? .always : .never))
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
            )
            .onTapGesture(count: 2, coordinateSpace: .named(FeedView.space)) { location in
                guard post.canRespond(model.viewer) else { return }
                model.react(.doubleTap, on: post, from: location)
            }
            .onTapGesture { open(page) }
            .photoViewer(isPresented: $isViewing, count: photoRefs.count, page: $photoPage, load: photo)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.photos")
    }

    /// Photo `index` of the cover's photos, for the viewer.
    private var photo: @Sendable (Int) async -> Data? {
        let refs = photoRefs
        let store = model.store
        return { index in
            guard refs.indices.contains(index) else { return nil }
            return await store.photo(refs[index])
        }
    }

    @ViewBuilder private func face(_ tile: Contracts.PostTile) -> some View {
        switch tile {
        case .photo(let ref):
            FeedPhoto(model: model, ref: ref)
        case .workout(.map):
            if let route = workout?.route {
                WorkoutMap(route: route, activity: activity).accessibilityIdentifier("feed.map")
            }
        case .workout(.chart):
            if let series = workout?.series {
                WorkoutChart(series: series, activity: activity, showsLabel: true)
                    .accessibilityIdentifier("feed.chart")
            }
        }
    }

    private func isPhoto(_ tile: Contracts.PostTile) -> Bool { if case .photo = tile { true } else { false } }

    /// Opens the photo on page `index` full screen; the map and chart stay where they are.
    private func open(_ index: Int) {
        guard tiles.indices.contains(index), case .photo(let ref) = tiles[index],
            let photo = photoRefs.firstIndex(of: ref)
        else { return }
        photoPage = photo
        isViewing = true
    }

    private func label(_ tile: Contracts.PostTile, index: Int) -> Text {
        switch tile {
        case .photo: Text(copy: "第 \(index + 1) 张，共 \(tiles.count) 张", bundle: .module)
        case .workout(.map): Text(copy: "路线地图，第 \(index + 1) 张，共 \(tiles.count) 张", bundle: .module)
        case .workout(.chart): Text(copy: "数据图，第 \(index + 1) 张，共 \(tiles.count) 张", bundle: .module)
        }
    }

    /// The design's 358 × 230 map and 358 × 180 chart.
    private static let mapAspect = 358.0 / 230
    private static let chartAspect = 358.0 / 180
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
