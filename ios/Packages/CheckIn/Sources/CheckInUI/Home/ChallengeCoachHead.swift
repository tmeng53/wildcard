#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystemUI
import SwiftUI

/// The head of the coach who set today's challenge, at the head of its row on the squad card:
/// the coach's own character, made once per coach. A coach this build has no
/// art for stands in as its silhouette (`MemberHead` without a player).
struct ChallengeCoachHead: View {
    let coach: CoachID?
    @State private var player: CharacterPlayer?

    init(_ coach: CoachSpeaker?) {
        self.coach = coach?.id
    }

    var body: some View {
        MemberHead(player: player, size: ChallengeRowLayout.head, figure: .coach)
            .task(id: coach) {
                guard let id = coach?.rawValue, CoachCharacter.exists(id) else {
                    player = nil
                    return
                }
                player = try? CharacterPlayer(
                    figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
            }
    }
}
#endif
