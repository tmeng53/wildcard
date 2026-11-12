#if os(iOS)
import AvatarUI
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
/// member's own. It is pushed on a NavigationStack, so the system's back button and swipe go back;
/// the tab bar is away while it is up. 动态 opens it from a card, and any screen with a
/// `FeedModel` over a store of one post (the member's past posts) shows the same page. `close`
/// goes back once the post is deleted here.
public struct PostDetailView: View {
    @Environment(\.sceneTheme) private var theme
    private let model: FeedModel
    private let id: CheckInID
    private let close: () -> Void
    @FocusState private var isTyping: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The comment held, lifted under its glass menu.
    @State private var holding: Comment.ID?

    private static let faceSize: Double = 32
    /// A held comment's lift.
    private static let liftScale = 1.03

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
                        // A check-in only recorded (发布到动态 off) is no post to talk under.
                        if post.checkIn.inFeed {
                            CommentComposer(model: model, post: post, isTyping: $isTyping)
                        }
                    }
            } else if model.store.phase != .loading {
                gone
            }
        }
        .pushedPage(hidesTabBar: true)
        .feedSurface(model)
        // Deleted from its own page, the page goes back.
        .managesPosts(model) { if $0 == id { close() } }
        .haptic(.pick, trigger: model.commentsSent)
        // Keyed by the post, so a comment's push that switches the open page to another post
        // loads that one.
        .task(id: id) {
            model.opened = id
            await model.loadPage(id)
        }
        // Back in the app, read it again: what came meanwhile, and a comment whose answer was
        // lost while away shows as saved.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.loadPage(id) } }
        }
        // However the page goes, the feed and tab bar stop treating the post as open.
        .onDisappear { if model.opened == id { model.opened = nil } }
    }

    private func page(_ post: FeedPost) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    PostCard(model: model, post: post)
                    comments(post).mentionTags(model)
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(model.lifted)
            // Pulled down, the page reads the post again: comments and reactions that came while
            // it was open and no notice told this member of. In a task of its own, since the
            // system cancels the pull's task once the spinner goes, which would cut off the
            // coach's read, the last step (as `FeedModel.load()` found).
            .refreshable { await Task { await model.loadPage(id) }.value }
            // The coach's answer to a reply comes after it was sent: bring it into view.
            .onChange(of: model.coachAnswers(on: post.id).count) { before, after in
                guard after > before, let last = model.coachAnswers(on: post.id).last else { return }
                withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                    reader.scrollTo(CommentThreadEntry.answerID(of: last), anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder private func comments(_ post: FeedPost) -> some View {
        let coach = model.coachReply(on: post.id).flatMap { $0.text == nil ? nil : $0 }
        let thread = model.thread(of: post)
        if thread.isEmpty && coach == nil {
            VStack(spacing: Space.xxs) {
                Text(copy: "还没有人说话", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                if post.author != model.viewer {
                    let author = model.displayName(of: post.author)
                    Text(copy: "说一句给\(author)打打气", bundle: .module)
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
                SectionLabel(Text(copy: "评论 \(count)", bundle: .module))
                if let coach, let text = coach.text {
                    replyToCoach(coach.coach) {
                        CoachCommentRow(
                            model: model, coach: coach.coach, text: text, mentions: coach.mentions,
                            writtenAt: coach.writtenAt)
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
                                model: model, coach: answer.coach, text: answer.text, mentions: answer.mentions,
                                writtenAt: answer.writtenAt, recipient: model.displayName(of: member))
                        }
                        .accessibilityIdentifier("post.coachAnswer")
                        .id(entry.id)
                    }
                }
            }
        }
    }

    /// The coach's line or answer, which a tap replies to (回复 毛头), as a teammate's comment.
    private func replyToCoach(_ coach: CoachSpeaker, @ViewBuilder label: () -> some View) -> some View {
        // A tap, not a button, so a tap on an @ tag in it opens that teammate's card instead.
        label()
            .contentShape(Rectangle())
            .onTapGesture { replyToCoach(coach) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { replyToCoach(coach) }
            .accessibilityHint(Text(copy: "回复", bundle: .module))
    }

    private func replyToCoach(_ coach: CoachSpeaker) {
        model.replyingTo = .coach(coach.id)
        isTyping = true
    }

    /// A comment: the writer's head, name and time, then 回复 and whom, then the words. A tap
    /// replies to a teammate's; holding one lifts it and opens the glass menu.
    private func row(_ comment: Comment, on post: FeedPost) -> some View {
        let isMine = comment.member == model.viewer
        let items = menu(for: comment, on: post)
        return HStack(alignment: .top, spacing: Space.s) {
            MemberHead(player: model.head(of: comment.member), size: Self.faceSize)
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
        .scaleEffect(holding == comment.id ? Self.liftScale : 1)
        .animation(.wildcard(Motion.press, reduceMotion: reduceMotion), value: holding)
        .onTapGesture { reply(to: comment) }
        .onLongPressGesture { holding = comment.id }
        .haptic(.pick, trigger: holding) { _, new in new == comment.id }
        .glassMenu(isPresented: isHolding(comment), items: items)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isMine ? [] : .isButton)
        .accessibilityHint(isMine ? Text(verbatim: "") : Text(copy: "回复", bundle: .module))
        .accessibilityAction { reply(to: comment) }
        .accessibilityActions {
            ForEach(items) { item in
                Button(action: item.action) { item.title }
            }
        }
        .accessibilityIdentifier("post.comment")
    }

    /// 回复 Mia: a teammate's comment only.
    private func reply(to comment: Comment) {
        guard comment.member != model.viewer else { return }
        model.replyingTo = .member(comment.member)
        isTyping = true
    }

    private func isHolding(_ comment: Comment) -> Binding<Bool> {
        Binding(get: { holding == comment.id }, set: { if !$0, holding == comment.id { holding = nil } })
    }

    /// Holding a comment: 复制, and 删除 on the member's own.
    private func menu(for comment: Comment, on post: FeedPost) -> [GlassMenuItem] {
        var items = [
            GlassMenuItem(Text(copy: "复制", bundle: .module), systemImage: "doc.on.doc", id: "post.comment.copy") {
                UIPasteboard.general.string = comment.text.text
            }
        ]
        if comment.member == model.viewer, !model.store.isSending(comment.id, on: post.id) {
            items.append(
                GlassMenuItem(
                    Text(copy: "删除", bundle: .module), systemImage: "trash", role: .destructive,
                    id: "post.comment.delete"
                ) {
                    Task { await model.store.deleteComment(comment.id, on: post.id) }
                })
        }
        return items
    }

    /// 回复 Mia：the words, with 回复 and the name in grey.
    private func words(of comment: Comment) -> Text {
        let words = model.words(of: comment).text(in: theme)
        guard let recipient = comment.replyTo.map({ model.displayName(of: $0) }) else { return words }
        let reply = Text(copy: "回复 \(recipient)：", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text(copy: "\(reply)\(words)", bundle: .module)
    }

    /// The post was deleted, or the member can't see it any more.
    private var gone: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(copy: "这条动态不见了", bundle: .module)
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
