#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI
import UIKit

/// One post, a ticket like the one it was written on (Tracy, 2026-11-08): its cover on top (its
/// photos and a 训练's map or chart, swiped, the first being the cover), or without any the shared
/// colour block with its words; the tear under it; on the stub a 训练's 成绩条 first, across the
/// card's width; then the author's whole character standing at the left, its head level with
/// their name, beside a column of their name, the time and what it was, 仅自己可见 on one shared to no
/// squad, the caption under a cover, and
/// at its foot who reacted with the comment and emoji buttons, so a reaction lands next to the
/// character that answers it; then, under a hairline, the coach's line and the latest comments. A
/// teammate reacts with the smiley button, by holding the card and sliding to an emoji, or with
/// a double tap on the cover or the block (❤️); the emoji flies to the author's character, which
/// answers with a move.
struct PostCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost

    /// The character's width at the card's left, the design's 80 points, head to feet.
    static let characterColumn: Double = 80
    /// The rig's own margin left of the body, 30 of its 240 points, pulled into the card's
    /// padding so the body lines up with the cover's edge rather than the drawing's.
    static let characterInset: Double = characterColumn * 30 / 240
    /// The character's head starts this far down its drawing (the rig's 50 of 240 points), less the
    /// name's own room above its letters: lifted by it, the head is level with the name.
    static let characterLift: Double = characterColumn * 50 / 240 - Space.xs
    /// How long a press on the card takes to open the emoji bar.
    static let holdToPick: Double = 0.45
    /// Moving this far first makes the press a scroll.
    static let holdSlop: Double = 10
    /// How much the held card lifts over the blurred feed.
    static let liftScale: Double = 1.02

    private var canRespond: Bool { post.canRespond(model.viewer) }
    /// The cover's pages: the photos, and a 训练's map or chart where the member put it.
    private var tiles: [Contracts.PostTile] {
        if case .trained(let training) = post.checkIn.entry { return training.tiles }
        return (post.checkIn.photos?.all ?? []).map(Contracts.PostTile.photo)
    }
    /// Teammates' emoji, or the coach's.
    private var hasReactions: Bool {
        !post.reactions.isEmpty || model.coachReply(on: post.id)?.emoji != nil
    }
    /// On its own page the post lists every comment under the card instead.
    private var showsAllComments: Bool { model.opened == post.id }
    private var isLifted: Bool { model.lifted && model.picking == post.id }
    /// Teammates' comments, or the coach's line.
    private var hasComments: Bool { !post.comments.isEmpty || model.coachReply(on: post.id)?.text != nil }

    /// A 训练's 成绩条, when it has numbers to show.
    private var strip: (cells: [ScoreCell], activity: Contracts.Activity)? {
        guard case .trained(let training) = post.checkIn.entry else { return nil }
        let cells = ScoreCell.cells(of: training)
        return cells.isEmpty ? nil : (cells, training.activity)
    }

    var body: some View {
        CoverTicket(tear: strip == nil ? .mist : .color) {
            if tiles.isEmpty {
                block
            } else {
                PostPhotos(model: model, post: post, tiles: tiles)
            }
        } stub: {
            VStack(alignment: .leading, spacing: 0) {
                if let strip {
                    ScoreStrip(cells: strip.cells, activity: strip.activity, bottom: .square)
                }
                details
                if hasComments && !showsAllComments {
                    Rectangle()
                        .fill(Color(role: .borderDefault, in: theme))
                        .frame(height: 1)
                        .padding(.horizontal, Space.s)
                    CardComments(model: model, post: post)
                        .padding(.horizontal, Space.s)
                        .padding(.top, Space.xs)
                        .padding(.bottom, Space.s)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.canManage(post) {
                manageMenu.padding(Space.s)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
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
                        Text(copy: "回应 \(emoji.text)", bundle: .module)
                    }
                }
            }
            if !post.reactions.isEmpty {
                Button {
                    model.listing = post.id
                } label: {
                    Text(copy: "看谁回应了", bundle: .module)
                }
            }
        }
        .accessibilityIdentifier("feed.post")
    }

    /// 「…」 on the member's own post: 编辑 opens the compose page on it, 删除 asks first, in the menu.
    private var manageMenu: some View {
        HeaderMenu(
            Text(copy: "编辑或删除", bundle: .module), on: .ink,
            items: scoreCardItem + [
                GlassMenuItem(Text(copy: "编辑", bundle: .module), systemImage: "pencil", id: "post.edit") {
                    model.edit(post)
                },
                GlassMenuItem(
                    Text(copy: "删除", bundle: .module), systemImage: "trash", role: .destructive, id: "post.delete",
                    confirm: .init(
                        Text(copy: "删掉这条动态？", bundle: .module),
                        message: Text(copy: "队友的回应和评论也会一起删掉", bundle: .module),
                        label: Text(copy: "删除", bundle: .module), id: "post.delete.confirm")
                ) {
                    model.deleting = post.id
                },
            ]
        )
        .accessibilityIdentifier("post.manage")
    }

    /// 存成绩卡, first, on one of the member's own 训练.
    private var scoreCardItem: [GlassMenuItem] {
        guard model.canSaveScoreCard(post) else { return [] }
        return [
            GlassMenuItem(
                Text(copy: "存成绩卡", bundle: .module), systemImage: "square.and.arrow.down", id: "post.scoreCard"
            ) {
                model.openScoreCard(post)
            }
        ]
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
        guard let location, let index = model.slot(at: location), let from = model.slotCenter(index),
            let emoji = Emoji.quick(at: index)
        else { return }
        model.react(.pick(emoji), on: post, from: from)
    }

    /// A post without a cover: the shared colour block in its place, with its words on it. A
    /// double tap reacts as on a photo.
    private var block: some View {
        PostBlock(checkIn: post.checkIn, layout: .strip)
            .onTapGesture(count: 2, coordinateSpace: .named(FeedView.space)) { location in
                guard canRespond else { return }
                model.react(.doubleTap, on: post, from: location)
            }
    }

    /// The whole character, then who, when and what, the words under a cover, and at the foot who
    /// reacted with the buttons.
    private var details: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            PostCharacter(model: model, post: post, width: Self.characterColumn)
                .padding(.top, -Self.characterLift)
            VStack(alignment: .leading, spacing: Space.xxs) {
                byline
                if post.checkIn.audience.isOnlyMe { OnlyMeTag() }
                if !tiles.isEmpty { words.padding(.top, Space.xxs) }
                if case .trained(let training) = post.checkIn.entry, !training.trainedWith.isEmpty {
                    TrainedWithTag(model: model, members: training.trainedWith.members)
                        .padding(.top, Space.xxs)
                }
                Spacer(minLength: Space.xxs)
                HStack(spacing: 0) {
                    if hasReactions {
                        ReactionRow(model: model, post: post, part: .summary)
                    } else {
                        Spacer(minLength: 0)
                    }
                    ReactionRow(model: model, post: post, part: .buttons)
                }
            }
            .padding(.top, Space.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Space.s - Self.characterInset)
        .padding([.top, .trailing], Space.s)
        .padding(.bottom, Space.xs)
    }

    /// 我 下午11:02 · 训练 · 快走, and which day a 补打卡 counts for.
    private var byline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            authorName
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .layoutPriority(1)
            Group {
                Text(post.checkIn.createdAt.date, format: .dateTime.hour().minute())
                Text(verbatim: "·")
                kindTitle
                if let backfill = BackfillDay(post.checkIn) {
                    Text(verbatim: "·")
                    BackfillLabel(day: backfill)
                        .accessibilityIdentifier("post.backfill")
                }
            }
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .lineLimit(1)
    }

    private var authorName: Text {
        if post.author == model.viewer { return Text(copy: "我", bundle: .module) }
        return model.name(of: post.author).map { Text(verbatim: $0) } ?? Text(copy: "队友", bundle: .module)
    }

    private var kindTitle: Text {
        switch post.checkIn.entry {
        case .trained(let training): Text(copy: "训练 · \(training.activity.name)", bundle: .module)
        case .healthyMeal: Text(copy: "健康餐", bundle: .module)
        case .cheatMeal: Text(copy: "坦白放纵餐", bundle: .module)
        case .disclaimer(let note):
            if note.restDay { Text(copy: "休息", bundle: .module) } else { Text(copy: "请假条", bundle: .module) }
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

/// 补周日的: which day a 补打卡 counts for, after the post's time.
struct BackfillLabel: View {
    let day: BackfillDay

    var body: some View {
        switch day {
        case .yesterday: Text(copy: "补昨天的", bundle: .module)
        case .weekday(1): Text(copy: "补周一的", bundle: .module)
        case .weekday(2): Text(copy: "补周二的", bundle: .module)
        case .weekday(3): Text(copy: "补周三的", bundle: .module)
        case .weekday(4): Text(copy: "补周四的", bundle: .module)
        case .weekday(5): Text(copy: "补周五的", bundle: .module)
        case .weekday(6): Text(copy: "补周六的", bundle: .module)
        case .weekday: Text(copy: "补周日的", bundle: .module)
        case .weekdayLastWeek(1): Text(copy: "补上周一的", bundle: .module)
        case .weekdayLastWeek(2): Text(copy: "补上周二的", bundle: .module)
        case .weekdayLastWeek(3): Text(copy: "补上周三的", bundle: .module)
        case .weekdayLastWeek(4): Text(copy: "补上周四的", bundle: .module)
        case .weekdayLastWeek(5): Text(copy: "补上周五的", bundle: .module)
        case .weekdayLastWeek(6): Text(copy: "补上周六的", bundle: .module)
        case .weekdayLastWeek: Text(copy: "补上周日的", bundle: .module)
        }
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
