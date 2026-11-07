#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Under a card's emoji row: the coach's line first, with the 教练 tag, then the latest two
/// comments or coach's answers, each its writer's name then the words (回复 Mia first when it
/// replies), two lines at most, then 全部 N 条评论 when there are more. A tap opens the post's own page, where all of
/// them are.
struct CardComments: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost

    var body: some View {
        Button {
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { model.openPage(post.id) }
        } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                if let reply = model.coachReply(on: post.id), let text = reply.text {
                    CoachCommentLine(coach: reply.coach, text: text)
                        .lineLimit(2)
                }
                let answers = model.coachAnswers(on: post.id)
                ForEach(post.threadOnCard(answers: answers)) { entry in
                    switch entry {
                    case .comment(let comment):
                        CommentLine(model: model, comment: comment)
                            .lineLimit(2)
                    case .answer(let answer, let member):
                        CoachCommentLine(
                            coach: answer.coach, text: answer.text, recipient: model.displayName(of: member)
                        )
                        .lineLimit(2)
                    }
                }
                let thread = post.thread(answers: answers)
                if thread.count > FeedPost.cardComments {
                    // The coach's line counts, as on the post's own page.
                    let count = thread.count + (model.coachReply(on: post.id)?.text == nil ? 0 : 1)
                    Text(copy: "全部 \(count) 条评论", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .padding(.top, Space.xxs / 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text(copy: "看全部评论", bundle: .module))
        .accessibilityIdentifier("feed.comments")
    }
}

/// One comment as a line of text: the writer's name in bold, 回复 and whom it replies to in grey,
/// then the words.
struct CommentLine: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let comment: Comment

    var body: some View {
        line
            .typeStyle(TypeRamp.callout)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var line: Text {
        let name = Text(verbatim: model.displayName(of: comment.member)).fontWeight(.semibold)
        let words = Text(model.words(of: comment))
        guard let recipient = comment.replyTo.map({ model.displayName(of: $0) }) else {
            return Text(copy: "\(name)  \(words)", bundle: .module)
        }
        let reply = Text(copy: "回复 \(recipient)", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text(copy: "\(name) \(reply)  \(words)", bundle: .module)
    }
}
#endif
