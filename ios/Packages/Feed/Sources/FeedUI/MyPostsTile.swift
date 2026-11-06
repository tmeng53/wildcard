#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI

/// 我的动态's tile on 我: how many posts the member made, and their three newest as squares across
/// the tile's foot (the cover photo, or the post's colour with a 练了's minutes), opening the wall. It reads the
/// wall's first page each time 我 shows it.
public struct MyPostsTile: View {
    private let store: PostWallStore
    private let open: () -> Void

    public init(store: PostWallStore, open: @escaping () -> Void) {
        self.store = store
        self.open = open
    }

    public var body: some View {
        GlanceTile(
            figure: Text(verbatim: store.counts.map { "\($0.posts)" } ?? "–"),
            title: Text("我的动态", bundle: .module), action: open
        ) {
            HStack(spacing: Space.xxs) {
                ForEach(0..<GlanceTileMetrics.posts, id: \.self) { index in
                    if index < store.posts.count {
                        PostThumbnail(store: store, post: store.posts[index])
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("me.myPosts")
        .task { await store.load() }
    }
}

/// One newest post on the tile: the shared `PostBlock` at thumbnail size, with a faint edge so a
/// 请假条's graphite shows on the graphite tile.
private struct PostThumbnail: View {
    let store: PostWallStore
    let post: FeedPost
    @State private var cover: CGImage?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                PostBlock(
                    checkIn: post.checkIn, photo: cover.map { Image(decorative: $0, scale: 1) }, layout: .thumbnail
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                    .strokeBorder(Color(role: .fgOnInkMuted, in: theme).opacity(0.4), lineWidth: Sizing.hairline)
            }
            .task(id: post.checkIn.photos?.cover.loadID) {
                guard cover == nil, let ref = post.checkIn.photos?.cover, let jpeg = await store.photo(ref) else {
                    return
                }
                cover = await PostTile.thumbnail(jpeg)
            }
    }
}
#endif
