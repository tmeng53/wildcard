import Contracts

/// One line among a post's comments: a member's comment, or the coach's answer to a member's
/// reply to it, which reads as a reply to that member.
public enum CommentThreadEntry: Hashable, Sendable, Identifiable {
    case comment(Comment)
    /// The coach's answer, and whom it answers.
    case answer(CoachAnswer, answering: MemberID)

    public var id: String {
        switch self {
        case .comment(let comment): "comment-\(comment.id)"
        case .answer(let answer, _): Self.answerID(of: answer)
        }
    }

    /// The entry's `id` for the coach's answer.
    public static func answerID(of answer: CoachAnswer) -> String { "answer-\(answer.comment)" }
}

extension FeedPost {
    /// The post's comments oldest first, each of the coach's answers right after the reply it
    /// answers. An answer whose reply is gone goes with it.
    public func thread(answers: [CoachAnswer]) -> [CommentThreadEntry] {
        let byReply = Dictionary(answers.map { ($0.comment, $0) }, uniquingKeysWith: { first, _ in first })
        return comments.flatMap { comment -> [CommentThreadEntry] in
            guard let answer = byReply[comment.id] else { return [.comment(comment)] }
            return [.comment(comment), .answer(answer, answering: comment.member)]
        }
    }

    /// The latest of them the card shows, oldest first.
    public func threadOnCard(answers: [CoachAnswer]) -> ArraySlice<CommentThreadEntry> {
        thread(answers: answers).suffix(Self.cardComments)
    }
}
