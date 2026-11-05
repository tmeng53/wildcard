#if os(iOS)
import AvatarUI
import ChatDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// One message as the chat shows it: a teammate's or the coach's at the left under its writer's
/// head and name (the coach's with the 教练 tag), mine at the right; what it replies to over it,
/// its emoji at its top corner, and, for mine that didn't go out, a 「!」 and 「点一下重发」.
/// Swiping it right replies to it; a long press lifts it.
struct MessageRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ChatModel
    let line: ChatStore.Line
    /// Whether it follows a message by the same writer close by, so its head and name are left out.
    let continues: Bool
    @State private var swipe: Double = 0

    static let head: Double = 32
    private static let replySwipe: Double = 56

    private var message: ChatMessage { line.message }
    private var isMine: Bool { message.member == model.store.viewer }
    private var style: MessageStyle {
        if case .coach = message.author { return .coach }
        return isMine ? .mine : .teammate
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.xs) {
            if isMine {
                Spacer(minLength: Space.xxl)
                if line.delivery == .failed { failedMark }
            } else {
                Group {
                    if continues {
                        Color.clear
                    } else {
                        MemberHead(
                            player: model.head(of: message.author), size: Self.head,
                            rim: style == .coach ? .coach : .mist)
                    }
                }
                .frame(width: Self.head, height: Self.head)
                .padding(.bottom, Space.xxs)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: Space.xxs) {
                if !isMine && !continues { writer }
                if let reply = message.replyTo, let original = model.store.message(reply) {
                    ReplyReference(original.text, style: style(of: original), leading: !isMine)
                }
                bubble
                if line.delivery == .failed {
                    Text("没发出去 · 点一下重发", bundle: .module)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            if !isMine { Spacer(minLength: Space.xxl) }
        }
        .offset(x: swipe)
        .overlay(alignment: .leading) {
            if swipe > 0 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: Sizing.smallIcon))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .opacity(min(swipe / Self.replySwipe, 1))
                    .offset(x: swipe - Space.l)
                    .accessibilityHidden(true)
            }
        }
        .simultaneousGesture(swipeToReply)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.message.\(message.id)")
    }

    private var writer: some View {
        HStack(spacing: Space.xxs) {
            Text(verbatim: model.name(of: message.author))
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
            if style == .coach { CoachTag(.small) }
        }
        .padding(.leading, Space.xxs)
    }

    private var bubble: some View {
        MessageBubble(style) { MentionText(message.text, mine: isMine) }
            .opacity(line.delivery == .sending ? 0.6 : 1)
            .overlay(alignment: isMine ? .topLeading : .topTrailing) { reactions }
            .padding(.top, message.reactions.isEmpty ? 0 : Space.xs)
            .onTapGesture {
                if line.delivery == .failed { Task { await model.store.retry(message.id) } }
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.lifted = message.id }
            }
            .accessibilityAction(named: Text("回复", bundle: .module)) { model.reply(to: message.id) }
            .accessibilityAction(named: Text("更多", bundle: .module)) { model.lifted = message.id }
    }

    @ViewBuilder private var reactions: some View {
        let counts = message.reactionCounts
        if !counts.isEmpty {
            ReactionBadge(emoji: counts.map(\.emoji.text), count: message.reactions.count) {
                model.whoReacted = message.id
            }
            .fixedSize()
            .offset(x: isMine ? -Space.s : Space.s, y: -Space.l)
            .accessibilityIdentifier("chat.reactions.\(message.id)")
        }
    }

    private var failedMark: some View {
        Button {
            Task { await model.store.retry(message.id) }
        } label: {
            Text(verbatim: "!")
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                .frame(width: Sizing.checkBadge, height: Sizing.checkBadge)
                .background(Color(role: .bgBrand, in: theme), in: Circle())
                .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("没发出去，点一下重发", bundle: .module))
        .accessibilityIdentifier("chat.retry")
    }

    private func style(of original: ChatMessage) -> MessageStyle {
        if case .coach = original.author { return .coach }
        return original.member == model.store.viewer ? .mine : .teammate
    }

    private var swipeToReply: some Gesture {
        DragGesture(minimumDistance: Space.m)
            .onChanged { drag in
                guard line.delivery == .sent, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                swipe = min(max(drag.translation.width, 0), Self.replySwipe * 1.2)
            }
            .onEnded { _ in
                if swipe >= Self.replySwipe { model.reply(to: message.id) }
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { swipe = 0 }
            }
    }
}

/// A message's words with each @name in bold, underlined, as the design marks them.
struct MentionText: View {
    let text: String
    let mine: Bool

    init(_ text: String, mine: Bool) {
        self.text = text
        self.mine = mine
    }

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var word = ""
        var inMention = false
        func flush() {
            guard !word.isEmpty else { return }
            var part = AttributedString(word)
            if inMention {
                part.inlinePresentationIntent = .stronglyEmphasized
                part.underlineStyle = .single
            }
            result += part
            word = ""
        }
        for character in text {
            if character == "@" {
                flush()
                inMention = true
            } else if inMention && character.isWhitespace {
                flush()
                inMention = false
            }
            word.append(character)
        }
        flush()
        return result
    }
}

/// The coach writing: its head and name, and its bubble with the app's three dots.
struct TypingRow: View {
    @Environment(\.sceneTheme) private var theme
    let model: ChatModel
    let coach: CoachID

    var body: some View {
        let name = model.name(of: .coach(coach))
        return HStack(alignment: .bottom, spacing: Space.xs) {
            MemberHead(player: model.head(ofCoach: coach), size: MessageRow.head, rim: .coach)
                .padding(.bottom, Space.xxs)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.xxs) {
                    Text(verbatim: name)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                    CoachTag(.small)
                }
                .padding(.leading, Space.xxs)
                MessageBubble(.coach) { LoadingDots(delay: 0) }
            }
            Spacer(minLength: Space.xxl)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name) 正在输入", bundle: .module))
        .accessibilityIdentifier("chat.coachTyping")
    }
}

/// The coach's 战术板 line of the day, as 动态's card: on a clipboard, its head, name and tag,
/// the time, the line, and its emoji.
struct NoteCard: View {
    @Environment(\.sceneTheme) private var theme
    let model: ChatModel
    let line: ChatStore.Line

    var body: some View {
        let message = line.message
        ClipboardCard {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    MemberHead(player: model.head(of: message.author), size: Sizing.characterHead, rim: .coach)
                    Text(verbatim: model.name(of: message.author))
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                    CoachTag(.small)
                    Spacer(minLength: 0)
                    Text(message.sentAt, format: .dateTime.hour().minute())
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                }
                MentionText(message.text, mine: false)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
                let counts = message.reactionCounts
                if !counts.isEmpty {
                    ReactionBadge(emoji: counts.map(\.emoji.text), count: message.reactions.count) {
                        model.whoReacted = message.id
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, Space.s + 2)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
        }
        .padding(.horizontal, Space.m)
        .onLongPressGesture(minimumDuration: 0.35) { model.lifted = message.id }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("战术板：\(message.text)", bundle: .module))
        .accessibilityIdentifier("chat.note")
    }
}
#endif
