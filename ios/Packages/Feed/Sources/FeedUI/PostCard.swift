#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI

/// One post: its photos on top (swipe; the cover first), the author's character standing at the
/// card's left in that day's kit, their name and time, the kind's tag, the caption or the
/// 请假条's text, then the emoji row. A teammate reacts with the
/// smiley button, a long press on the card or a double tap on a photo (❤️); the author's
/// character answers with a move.
struct PostCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost

    /// The column the character stands in, at the card's left.
    static let characterColumn: Double = 100
    /// How far the character's head reaches up into the photo above it.
    static let overlap: Double = Space.l

    private var canRespond: Bool { post.canRespond(model.viewer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photos = post.checkIn.photos {
                PostPhotos(model: model, post: post, photos: photos)
            }
            details
            ReactionRow(model: model, post: post)
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.m)
        }
        .background(
            Color(role: .bgSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(alignment: .topTrailing) { PopBadge(pop: model.pops[post.id]) }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.45) {
            guard canRespond else { return }
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.picking = post.id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.post")
    }

    /// The character's column, then who, when, what and the words.
    private var details: some View {
        HStack(alignment: .top, spacing: 0) {
            PostCharacter(model: model, post: post)
                .frame(width: Self.characterColumn)
                .padding(.top, post.checkIn.photos == nil ? Space.m : -Self.overlap)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs - 2) {
                    authorName
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                    Text(post.checkIn.createdAt.date.formatted(.dateTime.hour().minute()))
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
                Tag(kindTitle)
                words
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.s + (post.checkIn.photos == nil ? Space.xxs : 0))
            .padding(.trailing, Space.m)
            .padding(.bottom, Space.s)
        }
    }

    private var authorName: Text {
        if post.author == model.viewer { return Text("我", bundle: .module) }
        return model.name(of: post.author).map { Text(verbatim: $0) } ?? Text("队友", bundle: .module)
    }

    private var kindTitle: Text {
        switch post.checkIn.entry {
        case .trained(let training): Text("练了 · \(training.activity.name)", bundle: .module)
        case .healthyMeal: Text("健康餐", bundle: .module)
        case .cheatMeal: Text("坦白放纵餐", bundle: .module)
        case .disclaimer: Text("请假条", bundle: .module)
        }
    }

    /// The caption, or the 请假条's text, which is the card's hero.
    @ViewBuilder private var words: some View {
        switch post.checkIn.entry {
        case .trained(let training):
            if let caption = training.caption { captionText(caption.text) }
        case .healthyMeal(let meal), .cheatMeal(let meal):
            if let caption = meal.caption { captionText(caption.text) }
        case .disclaimer(let disclaimer):
            Text(verbatim: disclaimer.text)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func captionText(_ text: String) -> some View {
        Text(verbatim: text)
            .typeStyle(TypeRamp.body)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension CheckIn {
    var photos: Photos? {
        switch entry {
        case .trained(let training): training.photos
        case .healthyMeal(let meal), .cheatMeal(let meal): meal.photos
        case .disclaimer(let disclaimer): disclaimer.photos
        }
    }
}

/// The emoji that popped on the card when I reacted: a white circle that springs up, holds, and
/// fades, at my double tap or the card's top corner.
private struct PopBadge: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pop: FeedModel.Pop?

    private static let size: Double = 40

    var body: some View {
        GeometryReader { proxy in
            Text(verbatim: pop?.emoji.text ?? "")
                .font(.system(size: Self.size * 0.55))
                .frame(width: Self.size, height: Self.size)
                .background(Color(role: .bgCanvas, in: theme), in: Circle())
                .keyframeAnimator(initialValue: Burst(), trigger: pop?.count ?? 0) { badge, burst in
                    badge.scaleEffect(reduceMotion ? 1 : burst.scale).opacity(burst.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.2, duration: 0.3, spring: .snappy)
                        SpringKeyframe(1, duration: 0.2)
                        LinearKeyframe(1, duration: 0.8)
                        LinearKeyframe(0.8, duration: 0.3)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.05)
                        LinearKeyframe(1, duration: 1.25)
                        LinearKeyframe(0, duration: 0.3)
                    }
                }
                .position(pop?.point ?? CGPoint(x: proxy.size.width - Space.l, y: Space.xs))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Hidden until a pop: the animation runs from here and ends here.
    struct Burst {
        var scale = 0.0
        var opacity = 0.0
    }
}
#endif
