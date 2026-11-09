#if os(iOS)
import Contracts
import DesignSystemUI
import FeedDomain
import Foundation

// @ in comments: whom the box offers, and the 「@名字」 tags a comment or the coach's line shows.
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

    /// A comment's words, with the 「@名字」 of whom it @s as tags.
    func words(of comment: Comment) -> MentionedWords {
        var people = mentioned(comment.mentions.members)
        let unnamed = comment.mentions.members.filter { name(of: $0) == nil }
        if let id = comment.mentions.coach,
            let speaker = mentionableCoach?.id == id ? mentionableCoach : coach?.speaker(id)
        {
            people.append((.coach(id), speaker.name))
        }
        return MentionedWords(comment.text.text, people: people, unnamed: unnamed)
    }

    /// The coach's line or answer, with the 「@名字」 of the teammates it @s as tags.
    func words(of text: String, mentioning members: [MemberID]) -> MentionedWords {
        MentionedWords(text, people: mentioned(members), unnamed: members.filter { name(of: $0) == nil })
    }

    /// Teammates @'d, by the nickname their 「@」 carries; one the app can't name (who left the
    /// squad, or has no name yet) is greyed instead.
    private func mentioned(_ members: [MemberID]) -> [(person: MentionedWords.Person, name: String)] {
        members.compactMap { member in name(of: member).map { (.member(member), $0) } }
    }
}
#endif
