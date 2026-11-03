#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI
import UIKit

/// A post's own page: its card, the coach's line first, every comment oldest first with the
/// coach's answers among them, and the box to write one at the bottom. Tapping a teammate's
/// comment replies to them (回复 Mia), and tapping the coach's line or answer replies to the
/// coach (回复 毛头), which answers; holding a comment copies it, or deletes it when it is the
/// member's own. 返回 or a
/// swipe right goes back. 动态 opens it from a card, and any screen with a `FeedModel` over a
/// store of one post (the member's past posts) shows the same page.
public struct PostDetailView: View {
    @Environment(\.sceneTheme) private var theme
    private let model: FeedModel
    private let id: CheckInID
    private let close: () -> Void
    @FocusState private var isTyping: Bool

    private static let faceSize: Double = 32

    public init(model: FeedModel, post: CheckInID, close: @escaping () -> Void) {
        self.model = model
        self.id = post
        self.close = close
    }

    public var body: some View {
        ZStack {
            Color(role: .bgCanvas, in: theme).ignoresSafeArea()
            if let post = model.store.post(id) {
                page(post)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        CommentComposer(model: model, post: post, isTyping: $isTyping)
                    }
                    .swipesBack(perform: close)
            } else if model.store.phase != .loading {
                gone.swipesBack(perform: close)
            }
        }
        .feedSurface(model)
        .haptic(.pick, trigger: model.commentsSent)
        // Keyed by the post, so a comment's push that switches the open page to another post
        // loads that one.
        .task(id: id) {
            model.opened = id
            await model.loadPage(id)
        }
        // However the page goes, the feed and tab bar stop treating the post as open.
        .onDisappear { if model.opened == id { model.opened = nil } }
    }

    private var backButton: some View {
        HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
            .accessibilityIdentifier("post.back")
    }

    private func page(_ post: FeedPost) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                backButton
                PostCard(model: model, post: post)
                comments(post)
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollDisabled(model.lifted)
    }

    @ViewBuilder private func comments(_ post: FeedPost) -> some View {
        let coach = model.coachReply(on: post.id).flatMap { $0.text == nil ? nil : $0 }
        let thread = model.thread(of: post)
        if thread.isEmpty && coach == nil {
            VStack(spacing: Space.xxs) {
                Text("还没有人说话", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                if post.author != model.viewer {
                    let author = model.displayName(of: post.author)
                    Text("说一句给\(author)打打气", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.l)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("post.noComments")
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                let count = thread.count + (coach == nil ? 0 : 1)
                SectionLabel(Text("评论 \(count)", bundle: .module))
                if let coach, let text = coach.text {
                    replyToCoach(coach.coach) {
                        CoachCommentRow(model: model, coach: coach.coach, text: text, writtenAt: coach.writtenAt)
                    }
                    .accessibilityIdentifier("post.coachComment")
                }
                ForEach(thread) { entry in
                    switch entry {
                    case .comment(let comment):
                        row(comment, on: post)
                    case .answer(let answer, let member):
                        replyToCoach(answer.coach) {
                            CoachCommentRow(
                                model: model, coach: answer.coach, text: answer.text, writtenAt: answer.writtenAt,
                                recipient: model.displayName(of: member))
                        }
                        .accessibilityIdentifier("post.coachAnswer")
                    }
                }
            }
        }
    }

    /// The coach's line or answer, which a tap replies to (回复 毛头), as a teammate's comment.
    private func replyToCoach(_ coach: CoachSpeaker, @ViewBuilder label: () -> some View) -> some View {
        Button {
            model.replyingTo = .coach(coach.id)
            isTyping = true
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("回复", bundle: .module))
    }

    /// A comment: the writer's head, name and time, then 回复 and whom, then the words.
    private func row(_ comment: Comment, on post: FeedPost) -> some View {
        let isMine = comment.member == model.viewer
        return Button {
            guard !isMine else { return }
            model.replyingTo = .member(comment.member)
            isTyping = true
        } label: {
            HStack(alignment: .top, spacing: Space.s) {
                Face(player: model.head(of: comment.member), size: Self.faceSize)
                VStack(alignment: .leading, spacing: Space.xxs / 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text(verbatim: model.displayName(of: comment.member))
                            .typeStyle(TypeRamp.footnoteEmphasis)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .lineLimit(1)
                        Text(comment.commentedAt.date, format: .dateTime.hour().minute())
                            .typeStyle(TypeRamp.caption)
                            .foregroundStyle(Color(role: .fgSubtle, in: theme))
                            .lineLimit(1)
                    }
                    words(of: comment)
                        .typeStyle(TypeRamp.body)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: comment, on: post) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isMine ? Text(verbatim: "") : Text("回复", bundle: .module))
        .accessibilityIdentifier("post.comment")
    }

    /// Holding a comment: 复制, and 删除 on the member's own.
    @ViewBuilder private func menu(for comment: Comment, on post: FeedPost) -> some View {
        Button {
            UIPasteboard.general.string = comment.text.text
        } label: {
            Label {
                Text("复制", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
        if comment.member == model.viewer, !model.store.isSending(comment.id, on: post.id) {
            Button(role: .destructive) {
                Task { await model.store.deleteComment(comment.id, on: post.id) }
            } label: {
                Label {
                    Text("删除", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    /// 回复 Mia：the words, with 回复 and the name in grey.
    private func words(of comment: Comment) -> Text {
        guard let recipient = comment.replyTo.map({ model.displayName(of: $0) }) else {
            return Text(verbatim: comment.text.text)
        }
        let reply = Text("回复 \(recipient)：", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text("\(reply)\(comment.text.text)", bundle: .module)
    }

    /// The post was deleted, or the member can't see it any more.
    private var gone: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            backButton
            Text("这条动态不见了", bundle: .module)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .frame(maxWidth: .infinity)
                .padding(.top, Space.xxl)
                .accessibilityIdentifier("post.gone")
            Spacer()
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.xs)
    }
}
#endif
