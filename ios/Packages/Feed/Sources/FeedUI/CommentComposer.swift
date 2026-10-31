#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The box at the bottom of a post's own page: 回复 Mia with × when replying to someone, the
/// words (up to four lines, with the count near the limit) and the send button. Sent words leave
/// the box at once; if they couldn't go out they come back with a line saying so.
struct CommentComposer: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let post: FeedPost
    var isTyping: FocusState<Bool>.Binding
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendFailed = false

    /// Past this many characters the box shows how many are used.
    private static let countFrom = CommentText.maxLength - 20

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let recipient = model.replyingTo.map(model.displayName) {
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
            }
            if sendFailed {
                Text("网络开小差了，没发出去", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .accessibilityIdentifier("post.sendFailed")
            }
            HStack(alignment: .bottom, spacing: Space.xs) {
                field
                sendButton
            }
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.xs)
        .background(Color(role: .bgCanvas, in: theme))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(role: .borderDefault, in: theme)).frame(height: Sizing.hairline)
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: Space.xs) {
            TextField(text: $draft, axis: .vertical) {
                if let recipient = model.replyingTo.map(model.displayName) {
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
            .onChange(of: draft) { _, typed in
                sendFailed = false
                if typed.count > CommentText.maxLength { draft = String(typed.prefix(CommentText.maxLength)) }
            }
            if draft.count > Self.countFrom {
                Text(verbatim: "\(draft.count)/\(CommentText.maxLength)")
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
        let text = try? CommentText(draft)
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
        draft = ""
        isSending = true
        Task {
            let sent = await model.comment(text, on: post)
            isSending = false
            if !sent {
                draft = typed
                sendFailed = true
            }
        }
    }
}
#endif
