#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The emoji row at the bottom of a card: up to four heads, newest first, each wearing that
/// person's emoji, then +n for the rest; tapping them opens who reacted. At the right, my button:
/// a smiley that opens the emoji bar, or my emoji on the scene's wash once I reacted. My own
/// posts have no button, and no row until someone reacts.
struct ReactionRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost

    static let heads = 4
    private static let headSize: Double = 26
    private static let emojiSize: Double = 12
    private static let buttonSize = CGSize(width: 44, height: 34)
    private static let buttonEmojiSize: Double = 20
    private static let buttonPop: Double = 1.18

    private var canRespond: Bool { post.canRespond(model.viewer) }

    var body: some View {
        let reactions = post.reactions
        if canRespond || !reactions.isEmpty {
            HStack(spacing: Space.xs) {
                if !reactions.isEmpty {
                    summary(reactions, open: model.listing == post.id)
                }
                Spacer(minLength: 0)
                if canRespond {
                    myButton(reactions.kind(of: model.viewer), open: model.picking == post.id)
                }
            }
            .frame(height: Sizing.minimumTapTarget)
        }
    }

    // `open` is read in the body, so opening a panel redraws the row: SwiftUI calls an anchor's
    // transform outside the body, where reading the model isn't observed.
    private func summary(_ reactions: Responses<Emoji>, open: Bool) -> some View {
        Button {
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                model.closeBar()
                model.listing = post.id
            }
        } label: {
            HStack(spacing: Space.xxs) {
                ForEach(reactions.newest(Self.heads), id: \.member) { response in
                    WearingHead(model: model, member: response.member, emoji: response.kind, size: Self.headSize)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                let more = reactions.more(than: Self.heads)
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
        .accessibilityLabel(Self.summaryLabel(reactions))
        .accessibilityHint(Text("看谁回应了", bundle: .module))
        .accessibilityIdentifier("feed.reactions")
    }

    /// 「3 人回应：💪 2，😂 1」.
    static func summaryLabel(_ reactions: Responses<Emoji>) -> Text {
        let counts = reactions.groups.map { "\($0.kind.text) \($0.members.count)" }.joined(separator: "，")
        return Text("\(reactions.all.count) 人回应：\(counts)", bundle: .module)
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
                        .font(.system(size: Self.buttonEmojiSize, weight: .regular))
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
            .background(Color(role: mine == nil ? .bgCanvas : .bgAccentSubtle, in: theme), in: Capsule())
            .keyframeAnimator(initialValue: 1.0, trigger: mine) { button, scale in
                button.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(Self.buttonPop, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1, duration: 0.2)
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget)
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

/// A teammate's head on a white disc with a mist ring, wearing their emoji at its lower right.
struct WearingHead: View {
    let model: FeedModel
    let member: MemberID
    let emoji: Emoji?
    let size: Double

    var body: some View {
        Face(player: model.head(of: member), size: size)
            .overlay(alignment: .bottomTrailing) {
                if let emoji {
                    Text(verbatim: emoji.text)
                        .font(.system(size: size * 12 / 26))
                        .offset(x: size * 0.12, y: size * 0.08)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A teammate's head in a small white circle with a mist ring, as on the home's squad card.
struct Face: View {
    @Environment(\.sceneTheme) private var theme
    let player: CharacterPlayer?
    let size: Double

    var body: some View {
        Circle()
            .fill(Color(role: .bgCanvas, in: theme))
            .overlay {
                if let player {
                    CharacterHead(player: player).padding(Sizing.ringGap)
                }
            }
            .clipShape(Circle())
            .overlay { Circle().stroke(Color(role: .bgSubtle, in: theme), lineWidth: Sizing.ringGap) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
#endif
