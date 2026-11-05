#if os(iOS)
import Contracts
import DesignSystemUI
import FeedDomain
import Foundation

// @ in comments: whom the box offers, and the 「@名字」 a comment shows in bold.
extension FeedModel {
    /// The squad's coach now, which the box's 「@毛头」 and the @ list's first row @.
    var mentionableCoach: CoachSpeaker? { coach?.hired }

    /// Who may be @'d under a post, by nickname: its author and the squad, never anyone without a
    /// name yet.
    func mentionablePeople(on post: FeedPost) -> [MemberID: String] {
        var people = store.characters.mapValues(\.nickname.text)
        if people[post.author] == nil, let author = name(of: post.author) { people[post.author] = author }
        return people
    }

    /// Whom the @ list shows for what is typed after the `@`: the coach first, then the people,
    /// leaving out members once the comment @s as many as it may.
    func mentionCandidates(for draft: CommentDraft, on post: FeedPost) -> [Mentionable] {
        guard let query = draft.mentionQuery else { return [] }
        let all = CommentDraft.candidates(
            for: query, coach: mentionableCoach, people: mentionablePeople(on: post), viewer: viewer)
        return draft.canMentionMore ? all : all.filter(\.isCoach)
    }

    /// A comment's words with the 「@名字」 of whom it @s in bold.
    func words(of comment: Comment) -> AttributedString {
        var names = comment.mentions.members.compactMap { name(of: $0) }
        if let id = comment.mentions.coach,
            let speaker = mentionableCoach?.id == id ? mentionableCoach : coach?.speaker(id)
        {
            names.append(speaker.name)
        }
        return MentionHighlight.attributed(comment.text.text, names: names)
    }
}
#endif
