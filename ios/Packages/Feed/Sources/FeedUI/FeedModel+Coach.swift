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
