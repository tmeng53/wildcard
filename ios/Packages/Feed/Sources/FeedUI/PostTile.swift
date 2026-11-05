#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import ImageIO
import SportsUI
import SwiftUI

/// One post on 我的动态's wall: the shared `PostBlock` as a square, its cover photo or its colour
/// with its words, with its most-left emoji and everyone's count bottom right.
struct PostTile: View {
    let store: PostWallStore
    let post: FeedPost
    @State private var cover: CGImage?

    var body: some View {
        PostBlock(
            checkIn: post.checkIn, day: post.checkIn.day.day, photo: cover.map { Image(decorative: $0, scale: 1) },
            layout: .tile
        )
        .overlay(alignment: .bottomTrailing) {
            if let top = post.reactions.groups.first {
                let colors = PostBlockColors(checkIn: post.checkIn)
                Text(verbatim: "\(top.kind.text) \(post.reactions.all.count)")
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgDefault, in: colors.scene))
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xxs / 2)
                    .background(Color(role: .bgCanvas, in: colors.scene), in: Capsule())
                    .padding(Space.xxs)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.pick))
        .contentShape(RoundedRectangle(cornerRadius: Radius.pick))
        .accessibilityElement(children: .combine)
        .task(id: post.checkIn.photos?.cover.loadID) {
            guard cover == nil, let ref = post.checkIn.photos?.cover, let jpeg = await store.photo(ref) else {
                return
            }
            cover = await Self.thumbnail(jpeg)
        }
    }

    /// The cover cut down to the tile's size off the main actor, so scrolling the wall never
    /// decodes full photos.
    nonisolated static func thumbnail(_ jpeg: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
            ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
#endif
