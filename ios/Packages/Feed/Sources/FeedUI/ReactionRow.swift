#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// A card's reactions, in two parts. `summary`, under the card's words: the coach's head first
/// when it left an emoji, in its graphite ring, then up to four heads (three beside the
/// coach's), newest first, each wearing that person's emoji, then +n for the rest; tapping them
/// opens who reacted. `buttons`, at the right of the name and time: the comment button, then my
/// button, a smiley that opens the emoji bar, or my emoji, outlined, once I reacted, both round
/// Liquid Glass. My own posts have the comment button only.
struct ReactionRow: View {
    enum Part {
        case summary
        case buttons
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost
    let part: Part

    static let heads = 4
    private static let headSize: Double = 26
    private static let emojiSize: Double = 12
    /// The design's 36-point round buttons.
    private static let buttonSize = CGSize(width: Sizing.compactControl, height: Sizing.compactControl)
    private static let buttonEmojiSize: Double = 18
    private static let buttonGlyph: Double = 16
    private static let buttonPop: Double = 1.18
    private static let mineStroke: Double = 1.5

    private var canRespond: Bool { post.canRespond(model.viewer) }

    var body: some View {
        let reactions = post.reactions
        let coach = model.coachReply(on: post.id).flatMap { $0.emoji == nil ? nil : $0 }
        switch part {
        case .summary:
            HStack(spacing: 0) {
                if !reactions.isEmpty || coach != nil {
                    summary(reactions, coach: coach, open: model.listing == post.id)
                }
                Spacer(minLength: 0)
            }
            .frame(height: Sizing.minimumTapTarget)
        case .buttons:
            // Each button's tap area reaches 4 points past its circle, so they sit 8 apart.
            HStack(spacing: 0) {
                commentButton
                if canRespond {
                    myButton(reactions.kind(of: model.viewer), open: model.picking == post.id)
                }
            }
        }
    }

    /// Opens the post's own page to comment; anyone who sees the post comments, its author too.
    /// On the page itself it starts a comment to the post rather than to someone.
    private var commentButton: some View {
        Button {
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                if model.opened == post.id {
                    model.replyingTo = nil
                } else {
                    model.openPage(post.id)
                }
            }
        } label: {
            Image(systemName: "bubble")
                .font(.system(size: Self.buttonGlyph, weight: .regular))
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
                .glassEffect(.regular.interactive(), in: Circle())
                .frame(minWidth: Sizing.minimumTapTarget, minHeight: Sizing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("写评论", bundle: .module))
        .accessibilityIdentifier("feed.comment")
    }

    // `open` is read in the body, so opening a panel redraws the row: SwiftUI calls an anchor's
    // transform outside the body, where reading the model isn't observed.
    private func summary(_ reactions: Responses<Emoji>, coach: CoachReply?, open: Bool) -> some View {
        Button {
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                model.closeBar()
                model.listing = post.id
            }
        } label: {
            HStack(spacing: Space.xxs) {
                if let coach {
                    MemberHead(
                        player: model.coachPlayer(coach.coach.id), size: Self.headSize, figure: .coach,
                        emoji: coach.emoji?.text)
                }
                ForEach(reactions.newest(Self.teammateHeads(beside: coach)), id: \.member) { response in
                    MemberHead(player: model.head(of: response.member), size: Self.headSize, emoji: response.kind.text)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                let more = reactions.more(than: Self.teammateHeads(beside: coach))
                if more > 0 {
                    Text(verbatim: "+\(more)")
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .contentTransition(.numericText())
                        .padding(.leading, Space.xxs)
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: reactions)
        .anchorPreference(key: FeedAnchors.self, value: .bounds) { bounds in
            FeedAnchors.Value(who: open ? FeedAnchor(post: post.id, bounds: bounds) : nil)
        }
        .accessibilityLabel(Self.summaryLabel(reactions, coach: coach))
        .accessibilityHint(Text("看谁回应了", bundle: .module))
        .accessibilityIdentifier("feed.reactions")
    }

    /// Teammates' heads in the row: one fewer beside the coach's.
    private static func teammateHeads(beside coach: CoachReply?) -> Int { coach == nil ? heads : heads - 1 }

    /// 「3 人回应：💪 2，😂 1」, after 「教练 毛头：🔥」 when the coach left one.
    static func summaryLabel(_ reactions: Responses<Emoji>, coach: CoachReply? = nil) -> Text {
        let counts = reactions.groups.map { "\($0.kind.text) \($0.members.count)" }.joined(separator: "，")
        let members = Text("\(reactions.all.count) 人回应：\(counts)", bundle: .module)
        guard let coach, let emoji = coach.emoji else { return members }
        let coachSaid = Text("教练 \(coach.coach.name)：\(emoji.text)", bundle: .module)
        return reactions.isEmpty ? coachSaid : Text("\(coachSaid)，\(members)", bundle: .module)
    }

    private func myButton(_ mine: Emoji?, open: Bool) -> some View {
        Button {
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) {
                if model.picking == post.id {
                    model.closeBar()
                } else {
                    model.openBar(on: post.id, lifted: false)
                }
            }
        } label: {
            Group {
                if let mine {
                    Text(verbatim: mine.text).font(.system(size: Self.buttonEmojiSize))
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: Self.buttonGlyph, weight: .regular))
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
            .glassEffect(.regular.interactive(), in: Circle())
            // Once I reacted, a dark outline: 动态 is a brand screen, so no scene colour.
            .overlay {
                if mine != nil {
                    Circle().strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: Self.mineStroke)
                }
            }
            .keyframeAnimator(initialValue: 1.0, trigger: mine) { button, scale in
                button.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(Self.buttonPop, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1, duration: 0.2)
                }
            }
            .frame(minWidth: Sizing.minimumTapTarget, minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .anchorPreference(key: FeedAnchors.self, value: .bounds) { bounds in
            FeedAnchors.Value(bar: open ? FeedAnchor(post: post.id, bounds: bounds) : nil)
        }
        .accessibilityLabel(
            mine.map { Text("我的回应：\($0.text)", bundle: .module) } ?? Text("回应", bundle: .module)
        )
        .accessibilityIdentifier("feed.react")
    }
}

#endif
