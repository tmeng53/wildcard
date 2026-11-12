#if os(iOS)
import Contracts
import Foundation

/// The team's letter (感谢信, Tracy 2026-11-11): a broadcast with a letter flies in sealed over
/// 今天 the first time it is told, and opens again, unsealed, from its 通知 row or banner.
extension TodayModel {
    struct ShownTeamLetter: Equatable {
        let broadcast: Broadcast
        /// New on this phone: it flies in sealed. Opened again from 通知, it simply shows.
        let isSealed: Bool
        let shownAt: Date
    }

    /// Opens `broadcast`'s letter again, from its row in 通知 or its banner.
    public func showAgain(_ broadcast: Broadcast) {
        guard broadcast.letter != nil else { return }
        teamLetter = ShownTeamLetter(broadcast: broadcast, isSealed: false, shownAt: now())
    }

    /// The letter over 今天 now, once the scene is free for it: not while a check-in is being
    /// written, the burst is open or the squad is dropping in.
    var shownTeamLetter: ShownTeamLetter? {
        guard step == .scene, !isBurstOpen, arrival == nil else { return nil }
        return teamLetter
    }

    /// Whom the letter is to: the member's own nickname.
    var teamLetterRecipient: String {
        home?.today.members.first { $0.member == home?.member }?.character?.nickname.text ?? ""
    }

    /// 一会儿再说, 收下 or a tap around it: put away, its 通知 row read.
    func putAwayTeamLetter() {
        guard let shown = teamLetter else { return }
        teamLetter = nil
        broadcastOpened?(shown.broadcast)
    }

    /// 立刻穿上: what the team gave is put on through the app, which opens the wardrobe wearing it.
    func wearTeamLetter() {
        guard let shown = teamLetter, let presents = shown.broadcast.letter?.presents else { return }
        putAwayTeamLetter()
        teamLetterPlaces?.wear(presents)
    }
}
#endif
