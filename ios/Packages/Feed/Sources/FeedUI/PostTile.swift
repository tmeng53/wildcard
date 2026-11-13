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
                Text(verbatim: "\(top.kind.text) \(post.reactions.all.count)")
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgDefault, in: .gym))
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xxs / 2)
                    .background(Color(role: .bgCanvas, in: .gym), in: Capsule())
                    .padding(Space.xxs)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.pick))
        .contentShape(RoundedRectangle(cornerRadius: Radius.pick))
        .accessibilityElement(children: .combine)
        .task(id: post.checkIn.photos?.cover.loadID) {
            // An edit can swap or remove the cover: the old one stays only until the new one is in.
            guard let ref = post.checkIn.photos?.cover else {
                cover = nil
                return
            }
            guard let jpeg = await store.photo(ref) else {
                // Never keep a cover the post no longer has.
                if !Task.isCancelled { cover = nil }
                return
            }
            cover = await CoverThumbnail.make(jpeg)
        }
    }
}

/// A post's cover cut down to a tile's size off the main actor, so scrolling a wall of tiles
/// (我的动态, a place's page) never decodes full photos.
public enum CoverThumbnail {
    public static func make(_ jpeg: Data) async -> CGImage? {
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
