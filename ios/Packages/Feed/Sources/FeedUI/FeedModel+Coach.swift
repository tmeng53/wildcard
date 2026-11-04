#if os(iOS)
import AvatarArt
import AvatarUI
import Contracts
import FeedDomain
import Foundation

// The squad's coach on 动态: its 战术板 line on today, and its replies under posts, each with the
// 教练 tag.
extension FeedModel {
    /// The week before, then the coach's replies to its posts.
    func loadEarlier() async {
        await store.loadEarlier()
        await coach?.loadNew(store.sections.flatMap { $0.posts.map(\.id) })
    }

    /// A post's own page, with the coach's reply to it read again.
    func loadPage(_ post: CheckInID) async {
        await store.loadPost(post)
        await coach?.load(about: [post])
    }

    /// The 战术板 line while its day lasts.
    var coachNote: CoachNote? { coach?.todaysNote }

    /// What the coach said or left on a post.
    func coachReply(on post: CheckInID) -> CoachReply? { coach?.reply(to: post) }

    /// The coach's answers to replies to it under a post, oldest first.
    func coachAnswers(on post: CheckInID) -> [CoachAnswer] { coach?.answers(on: post) ?? [] }

    /// A post's comments with the coach's answers among them, as its page lists them.
    func thread(of post: FeedPost) -> [CommentThreadEntry] { post.thread(answers: coachAnswers(on: post.id)) }

    /// Whom a reply goes to, by name: a member's, or the coach's.
    func displayName(of target: ReplyTarget) -> String {
        switch target {
        case .member(let member): displayName(of: member)
        case .coach(let id): coach?.speaker(id)?.name ?? String(localized: "教练", bundle: .module.inAppLanguage)
        }
    }

    /// A coach's character, standing still: nil for a coach this build has no art for, which
    /// shows its name and tag without a face.
    func coachPlayer(_ coach: CoachID) -> CharacterPlayer? {
        if let player = coachPlayers[coach] { return player }
        guard CoachCharacter.exists(coach.rawValue),
            let player = try? CharacterPlayer(
                figure: CoachCharacter.figure(coach.rawValue), idle: CoachCharacter.clip(.idle, coach: coach.rawValue))
        else { return nil }
        coachPlayers[coach] = player
        return player
    }
}
#endif
