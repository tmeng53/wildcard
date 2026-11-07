#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The box at the bottom of a post's own page, floating in Liquid Glass over the comments as
/// the approved comment composer does: 回复 Mia with × when replying to someone, 「@毛头」 while the
/// squad has a coach, the words (up to four lines, with the count near the limit) and the send
/// button; typing `@` opens the @ list over it, the coach first. Sent words leave the box at
/// once; if they couldn't go out they come back with a line saying so.
struct CommentComposer: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let post: FeedPost
    var isTyping: FocusState<Bool>.Binding
    @State private var draft = CommentDraft()
    @State private var isSending = false
    /// The words that couldn't go out, back in the box; the line saying so shows until they change.
    @State private var unsent: String?

    /// Past this many characters the box shows how many are used.
    private static let countFrom = CommentText.maxLength - 20

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            let candidates = model.mentionCandidates(for: draft, on: post)
            if !candidates.isEmpty {
                PersonPicker(
                    candidates, name: \.name, isCoach: \.isCoach, identifier: "post.mention",
                    head: { person in head(of: person) },
                    pick: { person in
                        draft.pick(person)
                        isTyping.wrappedValue = true
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let unsent, unsent == draft.text {
                InlineFailure(Text("网络开小差了，没发出去", bundle: .module))
                    .accessibilityIdentifier("post.sendFailed")
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                if let recipient = model.replyingTo.map({ model.displayName(of: $0) }) {
                    replying(to: recipient)
                }
                HStack(alignment: .bottom, spacing: Space.xs) {
                    if let coach = model.mentionableCoach { mentionCoach(coach) }
                    field
                    sendButton
                }
            }
            .padding(Space.xs - 2)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card + 12, style: .continuous))
            // A container, so its identifier doesn't replace those of ×, the field and send.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("post.composer")
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.bottom, Space.xs)
    }

    private func replying(to recipient: String) -> some View {
        HStack(spacing: Space.xs) {
            Text("回复 \(recipient)", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                model.replyingTo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Sizing.minimumTapTarget, height: Space.l)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("不回复了", bundle: .module))
            .accessibilityIdentifier("post.cancelReply")
        }
        .padding(.leading, Space.s)
    }

    /// 「@毛头」: puts the coach in the words, as picking it from the @ list does.
    private func mentionCoach(_ coach: CoachSpeaker) -> some View {
        Button {
            draft.pick(.coach(coach))
            isTyping.wrappedValue = true
        } label: {
            Text(verbatim: "@\(coach.name)")
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .padding(.horizontal, Space.s)
                .frame(height: Sizing.compactControl)
                .background(Color(role: .bgSubtle, in: theme), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("post.mentionCoach")
    }

    private func head(of person: Mentionable) -> some View {
        switch person {
        case .coach(let coach):
            MemberHead(player: model.coachPlayer(coach.id), size: Sizing.characterHead, figure: .coach)
        case .member(let member, _):
            MemberHead(player: model.head(of: member), size: Sizing.characterHead)
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: Space.xs) {
            TextField(text: $draft.text, axis: .vertical) {
                if let recipient = model.replyingTo.map({ model.displayName(of: $0) }) {
                    Text("回复 \(recipient)…", bundle: .module)
                } else if post.author == model.viewer {
                    Text("说点什么…", bundle: .module)
                } else {
                    let author = model.displayName(of: post.author)
                    Text("给\(author)说点什么…", bundle: .module)
                }
            }
            .typeStyle(TypeRamp.field)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(1...4)
            .focused(isTyping)
            .accessibilityIdentifier("post.field")
            .onChange(of: draft.text) { _, typed in
                if typed.count > CommentText.maxLength { draft.text = String(typed.prefix(CommentText.maxLength)) }
            }
            if draft.text.count > Self.countFrom {
                Text(verbatim: "\(draft.text.count)/\(CommentText.maxLength)")
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(minHeight: Sizing.compactControl)
        .background(
            Color(role: .bgSubtle, in: theme),
            in: RoundedRectangle(cornerRadius: Sizing.compactControl / 2, style: .continuous))
    }

    private var sendButton: some View {
        let text = try? CommentText(draft.text)
        return Button {
            guard let text else { return }
            send(text, on: post.id)
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                .background(Color(role: .bgBrand, in: theme), in: Circle())
                .opacity(text == nil || isSending ? 0.35 : 1)
                .frame(minWidth: Sizing.minimumTapTarget, minHeight: Sizing.compactControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(text == nil || isSending)
        .accessibilityLabel(Text("发送", bundle: .module))
        .accessibilityIdentifier("post.send")
    }

    /// The words leave the box at once and show in the list; if they couldn't go out they come
    /// back to try again.
    private func send(_ text: CommentText, on post: CheckInID) {
        let typed = draft
        draft.clear()
        unsent = nil
        isSending = true
        Task {
            let sent = await model.comment(text, mentioning: typed.mentions, on: post)
            isSending = false
            // Words typed meanwhile stay: the unsent ones come back only to an empty box.
            if !sent, draft.text.isEmpty {
                draft = typed
                unsent = typed.text
            }
        }
    }
}
#endif
