#if os(iOS)
import AvatarUI
import ChatDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI
import UIKit

/// The floating glass composer: 「@毛头」 while the squad has a coach, the field, and send; the
/// @ picker over it while an `@` is typed, and what the member is replying to over that.
struct ComposerBar: View {
    @Environment(\.sceneTheme) private var theme
    @Bindable var model: ChatModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Space.xs) {
            let candidates = model.mentionCandidates
            if !candidates.isEmpty {
                PersonPicker(
                    candidates, name: \.name, isCoach: { if case .coach = $0 { true } else { false } },
                    identifier: "chat.mention",
                    head: { person in
                        MemberHead(player: head(of: person), size: Sizing.characterHead, rim: rim(of: person))
                    },
                    pick: { person in model.pick(person) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let reply = model.composer.replyTo, let original = model.store.message(reply) {
                replying(to: original)
            }
            HStack(spacing: Space.xs) {
                if model.store.coaches.current != nil {
                    Button {
                        model.mentionCoach()
                        focused = true
                    } label: {
                        Text(verbatim: "@\(model.store.coaches.current?.name ?? "")")
                            .typeStyle(TypeRamp.calloutEmphasis)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .lineLimit(1)
                            .padding(.horizontal, Space.s)
                            .frame(height: Sizing.compactControl)
                            .background(Color(role: .bgSubtle, in: theme), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("chat.mentionCoach")
                }
                TextField(
                    text: $model.composer.text, prompt: Text("说点什么…", bundle: .module), axis: .vertical
                ) {
                    Text("说点什么…", bundle: .module)
                }
                .typeStyle(TypeRamp.field)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, Space.s + 2)
                .padding(.vertical, Space.xs)
                .frame(minHeight: Sizing.compactControl)
                .background(
                    Color(role: .bgSubtle, in: theme),
                    in: RoundedRectangle(cornerRadius: Radius.card + 6, style: .continuous)
                )
                .accessibilityIdentifier("chat.field")
                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: Sizing.smallIcon, weight: .bold))
                        .foregroundStyle(Color(role: canSend ? .fgOnBrand : .fgSubtle, in: theme))
                        .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                        .background(Color(role: canSend ? .bgBrand : .bgSubtle, in: theme), in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSend)
                .accessibilityLabel(Text("发送", bundle: .module))
                .accessibilityIdentifier("chat.send")
            }
            .padding(Space.xs - 2)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card + 12, style: .continuous))
        }
        .onChange(of: model.composer.replyTo) { _, reply in
            if reply != nil { focused = true }
        }
    }

    private var canSend: Bool { model.composer.draft != nil }

    private func replying(to original: ChatMessage) -> some View {
        let name = model.name(of: original.author)
        return HStack(spacing: Space.xs) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: Sizing.smallIcon))
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            Text("回复 \(name)", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .fixedSize()
            Text(verbatim: original.text)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                model.composer.replyTo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.compactControl)
            }
            .accessibilityLabel(Text("不回复了", bundle: .module))
            .accessibilityIdentifier("chat.cancelReply")
        }
        .padding(.leading, Space.s)
        .glassEffect(.regular, in: Capsule())
        .accessibilityIdentifier("chat.replying")
    }

    private func head(of person: Mentionable) -> CharacterPlayer? {
        switch person {
        case .coach(let coach): model.head(ofCoach: coach.id)
        case .member(let member, _): model.head(of: member)
        }
    }

    private func rim(of person: Mentionable) -> MemberHead.Rim {
        if case .coach = person { return .coach }
        return .mist
    }
}

/// A long press on a message, as iMessage's: everything else blurs, the message stays where it was
/// lifted, the glass emoji bar over it and the glass menu under it, icons on the left. A tap
/// anywhere else puts it down.
struct LiftedMessage: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ChatModel
    let line: ChatStore.Line

    private static let menuWidth: Double = 220
    private static let pickerHeight: Double = 260

    private var isMine: Bool { line.message.member == model.store.viewer }

    var body: some View {
        ZStack {
            Color(role: .bgCanvas, in: theme).opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { putDown() }
                .accessibilityAction(named: Text("关闭", bundle: .module)) { putDown() }
            VStack(alignment: isMine ? .trailing : .leading, spacing: Space.xs) {
                Spacer(minLength: 0)
                if line.delivery == .sent {
                    if model.browsing {
                        EmojiPicker(
                            recent: [], all: Emoji.all, text: \.text, mine: model.store.myReaction(on: line.id),
                            identifier: "chat.emoji"
                        ) { emoji in
                            model.react(emoji, on: line.id)
                        }
                        .frame(height: Self.pickerHeight)
                    } else {
                        ReactionBar(
                            Emoji.quick, text: \.text, mine: model.store.myReaction(on: line.id),
                            identifier: "chat.emoji"
                        ) { index in
                            model.react(Emoji.quick[index], on: line.id)
                        } more: {
                            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.browsing = true }
                        }
                        .fixedSize()
                    }
                }
                if line.message.kind == .note {
                    NoteCard(model: model, line: line).allowsHitTesting(false)
                } else {
                    MessageRow(model: model, line: line, continues: false).allowsHitTesting(false)
                }
                menu
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s + 2)
            .haptic(.pick, trigger: line.id)
        }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            ForEach(model.store.actions(for: line.id), id: \.self) { action in
                Button {
                    run(action)
                } label: {
                    HStack(spacing: Space.s - 2) {
                        Image(systemName: symbol(action))
                            .font(.system(size: Sizing.smallIcon + 2, weight: .medium))
                            .frame(width: Sizing.icon)
                        title(action).typeStyle(TypeRamp.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color(role: action == .delete ? .fgDanger : .fgDefault, in: theme))
                    .padding(.horizontal, Space.s + 2)
                    .frame(height: Sizing.control)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("chat.menu.\(String(describing: action))")
            }
        }
        .padding(Space.xxs + 2)
        .frame(width: Self.menuWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card + 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .padding(.leading, isMine ? 0 : MessageRow.head + Space.xs)
    }

    private func run(_ action: MessageAction) {
        switch action {
        case .reply: model.reply(to: line.id)
        case .copy:
            UIPasteboard.general.string = line.message.text
            putDown()
        case .report: model.report(line.id)
        case .delete: model.delete(line.id)
        }
    }

    private func putDown() {
        withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) {
            model.lifted = nil
            model.browsing = false
        }
    }

    private func symbol(_ action: MessageAction) -> String {
        switch action {
        case .reply: "arrowshape.turn.up.left"
        case .copy: "doc.on.doc"
        case .report: "exclamationmark.bubble"
        case .delete: "trash"
        }
    }

    private func title(_ action: MessageAction) -> Text {
        switch action {
        case .reply: Text("回复", bundle: .module)
        case .copy: Text("复制", bundle: .module)
        case .report: Text("举报", bundle: .module)
        case .delete: Text("删除", bundle: .module)
        }
    }
}

/// Who reacted to a message: each person's head, name and emoji, as 动态's panel shows them.
struct WhoReacted: View {
    @Environment(\.sceneTheme) private var theme
    let model: ChatModel
    let message: ChatMessage

    private static let width: Double = 300
    private static let row: Double = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(message.reactions, id: \.member) { reaction in
                    HStack(spacing: Space.s) {
                        MemberHead(player: model.head(of: reaction.member), size: Sizing.characterHead)
                        Text(verbatim: name(reaction.member))
                            .typeStyle(TypeRamp.body)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: reaction.emoji.text).typeStyle(TypeRamp.headline)
                    }
                    .frame(height: Self.row)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width)
        .frame(maxHeight: Self.row * 5.5 + 2 * Space.xs)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityIdentifier("chat.who")
    }

    private func name(_ member: MemberID) -> String {
        if member == model.store.viewer { return String(localized: "我", bundle: .module.inAppLanguage) }
        return model.name(of: .member(member))
    }
}
#endif
