#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI
import UIKit

/// One post: its photos on top (swipe; the cover first), the author's character standing at the
/// card's left in that day's kit, their name and time, the kind's tag (a 请假条's grey with a
/// moon), the caption or the 请假条's text, then the emoji row. A teammate reacts with the
/// smiley button, by holding the card and sliding to an emoji, or with a double tap on a photo
/// (❤️); the emoji flies to the author's character, which answers with a move.
struct PostCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost

    /// The column the character stands in, at the card's left.
    static let characterColumn: Double = 100
    /// How far the character's head reaches up into the photo above it.
    static let overlap: Double = Space.l
    /// How long a press on the card takes to open the emoji bar.
    static let holdToPick: Double = 0.45
    /// Moving this far first makes the press a scroll.
    static let holdSlop: Double = 10
    /// How much the held card lifts over the blurred feed.
    static let liftScale: Double = 1.02

    private var canRespond: Bool { post.canRespond(model.viewer) }
    private var isLifted: Bool { model.lifted && model.picking == post.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photos = post.checkIn.photos {
                PostPhotos(model: model, post: post, photos: photos)
            }
            details
            ReactionRow(model: model, post: post)
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.xs)
        }
        .background(
            Color(role: .bgSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .gesture(HoldAndSlide(isEnabled: canRespond, held: hold(at:), letGo: letGo(at:)))
        .scaleEffect(isLifted && !reduceMotion ? Self.liftScale : 1)
        .blur(radius: model.lifted && !isLifted ? Scrim.blurRadius : 0)
        .zIndex(isLifted ? 1 : 0)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: isLifted)
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if canRespond {
                ForEach(EmojiBar.common, id: \.self) { emoji in
                    Button {
                        model.react(.pick(emoji), on: post)
                    } label: {
                        Text("回应 \(emoji.text)", bundle: .module)
                    }
                }
            }
            if !post.reactions.isEmpty {
                Button {
                    model.listing = post.id
                } label: {
                    Text("看谁回应了", bundle: .module)
                }
            }
        }
        .accessibilityIdentifier("feed.post")
    }

    /// Held on the card: the bar opens over it, and the finger's place picks the slot under it.
    private func hold(at location: CGPoint) {
        if !isLifted {
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) {
                model.openBar(on: post.id, lifted: true)
            }
        }
        model.hovering = model.slot(at: location)
    }

    /// Let go on an emoji to pick it; anywhere else (or cancelled) leaves the bar open for a tap.
    private func letGo(at location: CGPoint?) {
        model.hovering = nil
        guard let location, let index = model.slot(at: location), let from = model.slotCenter(index) else { return }
        model.react(.pick(EmojiBar.common[index]), on: post, from: from)
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
                    if case .trained(let training) = post.checkIn.entry, let minutes = training.minutes {
                        Spacer(minLength: Space.xs)
                        minutesNumber(minutes)
                    }
                }
                if case .disclaimer = post.checkIn.entry {
                    Tag(kindTitle, systemImage: "moon.fill", style: .rest)
                } else {
                    Tag(kindTitle)
                }
                words
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.s + (post.checkIn.photos == nil ? Space.xxs : 0))
            .padding(.trailing, Space.m)
            .padding(.bottom, Space.s)
        }
    }

    /// A 练了's minutes, the card's one big number, at the right of who and when.
    private func minutesNumber(_ minutes: WorkoutMinutes) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
            Text(verbatim: "\(minutes.value)")
                .typeStyle(TypeRamp.scoreCard)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Text("分钟", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed.minutes")
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

/// Press and hold a card to open the emoji bar over it, then slide along the bar and let go on an
/// emoji to pick it. A UIKit long press, not a SwiftUI one: a SwiftUI gesture with a drag in it
/// keeps the feed from scrolling when a swipe starts on a card, even alongside the scroll. This
/// one fails once the finger moves first, so the scroll wins, and once it holds the scroll can't
/// start, so the slide only picks.
private struct HoldAndSlide: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    /// The press held, and each move after, in the feed's space.
    let held: (CGPoint) -> Void
    /// The finger lifted there, or the press was cancelled (nil).
    let letGo: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = PostCard.holdToPick
        recognizer.allowableMovement = PostCard.holdSlop
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .named(FeedView.space))
        switch recognizer.state {
        case .began, .changed: held(location)
        case .ended: letGo(location)
        case .cancelled, .failed: letGo(nil)
        default: break
        }
    }
}
#endif
