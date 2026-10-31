#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import ImageIO
import SportsUI
import SwiftUI

/// One post on 我的动态's wall: a square of its cover photo, or of its colour with its words
/// when it has none. Its day sits top left, its sport or kind top right, a 练了's minutes bottom
/// left and its most-left emoji with everyone's count bottom right.
struct PostTile: View {
    let store: PostWallStore
    let post: FeedPost
    @State private var cover: CGImage?

    var body: some View {
        let colors = TileColors(post.checkIn.entry)
        Color(role: colors.fill, in: colors.scene)
            .overlay {
                if let cover {
                    Image(decorative: cover, scale: 1).resizable().scaledToFill()
                } else if let words = post.checkIn.words {
                    Text(verbatim: words)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: colors.ink, in: colors.scene))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.xs)
                }
            }
            .overlay(alignment: .topLeading) {
                Text(verbatim: String(post.checkIn.day.day))
                    .typeStyle(TypeRamp.scoreCaption)
                    .padding(Space.xs)
            }
            .overlay(alignment: .topTrailing) {
                post.checkIn.wallLabel
                    .typeStyle(TypeRamp.caption)
                    .lineLimit(1)
                    .padding(Space.xs)
            }
            .overlay(alignment: .bottomLeading) {
                if let minutes = post.checkIn.minutes {
                    Text(verbatim: "\(minutes)′")
                        .typeStyle(TypeRamp.scoreSmall)
                        .padding(.horizontal, Space.xs)
                        .padding(.bottom, Space.xxs)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let top = post.reactions.groups.first {
                    Text(verbatim: "\(top.kind.text) \(post.reactions.all.count)")
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgDefault, in: colors.scene))
                        .padding(.horizontal, Space.xs)
                        .padding(.vertical, Space.xxs / 2)
                        .background(Color(role: .bgCanvas, in: colors.scene), in: Capsule())
                        .padding(Space.xxs)
                }
            }
            .foregroundStyle(Color(role: colors.ink, in: colors.scene))
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.pick))
            .contentShape(RoundedRectangle(cornerRadius: Radius.pick))
            .accessibilityElement(children: .combine)
            .task(id: post.checkIn.photos?.cover) {
                guard let ref = post.checkIn.photos?.cover, let jpeg = await store.photo(ref) else { return }
                cover = await Self.thumbnail(jpeg)
            }
    }

    /// The cover cut down to the tile's size off the main actor, so scrolling the wall never
    /// decodes full photos.
    private nonisolated static func thumbnail(_ jpeg: Data) async -> CGImage? {
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

/// A tile's colours. Only the design system's: a 练了 takes the scene its sport's category
/// belongs to, a meal the scene of its kind, and a 请假条 the brand's graphite.
struct TileColors {
    let scene: SceneTheme
    let fill: ColorRole
    let ink: ColorRole

    init(_ entry: CheckIn.Entry) {
        switch entry {
        case .trained(let training):
            self.init(scene: Self.scene(of: training.activity))
        case .healthyMeal:
            self.init(scene: .tennis)
        case .cheatMeal:
            self.init(scene: .track)
        case .disclaimer:
            self.init(scene: .gym, fill: .bgBrand, ink: .fgOnBrand)
        }
    }

    private init(scene: SceneTheme, fill: ColorRole = .bgAccent, ink: ColorRole = .fgOnAccent) {
        self.scene = scene
        self.fill = fill
        self.ink = ink
    }

    /// Each category of the sports list on a scene: Tracy's pick (2026-10-31). A category added
    /// later, or a sport people name themselves, takes the gym's.
    static let sceneByCategory: [String: SceneTheme] = [
        "runWalk": .track, "cardio": .track, "cycling": .track, "combat": .track,
        "water": .pool,
        "strength": .gym, "everyday": .gym,
        "racket": .tennis, "ball": .tennis,
        "outdoorWinter": .climbing, "mindBody": .climbing, "dance": .climbing,
    ]

    static func scene(of activity: Activity) -> SceneTheme {
        guard case .sport(let sport) = activity, let category = sport.entry?.category else { return .gym }
        return sceneByCategory[category] ?? .gym
    }
}

extension CheckIn {
    /// What a tile without a photo shows: the line or the 请假条's words.
    var words: String? {
        switch entry {
        case .trained(let training): training.caption?.text
        case .healthyMeal(let meal), .cheatMeal(let meal): meal.caption?.text
        case .disclaimer(let disclaimer): disclaimer.text
        }
    }

    /// A 练了's minutes, when it has them.
    var minutes: Int? {
        guard case .trained(let training) = entry else { return nil }
        return training.minutes?.value
    }

    /// The sport for a 练了, else the kind.
    var wallLabel: Text {
        switch entry {
        case .trained(let training): training.activity.cardName
        case .healthyMeal: Text("健康餐", bundle: .module)
        case .cheatMeal: Text("放纵餐", bundle: .module)
        case .disclaimer: Text("请假条", bundle: .module)
        }
    }
}
#endif
