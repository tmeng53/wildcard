#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Under a card's emoji row: the latest two comments, each its writer's name then the words (回复
/// Mia first when it replies), two lines at most, then 全部 N 条评论 when there are more. A tap
/// opens the post's own page, where all of them are.
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
                ForEach(post.commentsOnCard) { comment in
                    CommentLine(model: model, comment: comment)
                        .lineLimit(2)
                }
                if post.comments.count > FeedPost.cardComments {
                    Text("全部 \(post.comments.count) 条评论", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .padding(.top, Space.xxs / 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("看全部评论", bundle: .module))
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
        let words = comment.text.text
        guard let recipient = comment.replyTo.map(model.displayName) else {
            return Text("\(name)  \(words)", bundle: .module)
        }
        let reply = Text("回复 \(recipient)", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text("\(name) \(reply)  \(words)", bundle: .module)
    }
}
#endif
