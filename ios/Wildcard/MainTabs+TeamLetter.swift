import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystemUI
import MeDomain
import SportsUI
import SwiftUI

/// The team's letter on 今天 (感谢信, Tracy 2026-11-11): what the team gave, drawn from the
/// wardrobe and the member's badge board, and 立刻穿上, which opens 衣橱 trying it on.
extension MainTabs {
    /// What 今天 opens over itself: the coach's pages, and the team's letter's places.
    func opensPagesFromToday() {
        opensCoachPagesFromToday()
        today.teamLetterPlaces = teamLetterPlaces
    }

    private var teamLetterPlaces: TeamLetterPlaces {
        TeamLetterPlaces(
            picture: { [profile] present in TeamPresentPicture(present: present, profile: profile) },
            name: { [profile] present in
                switch present {
                case .piece(let piece): UnlockNames.piece(piece)
                case .badge(let badge):
                    Text(verbatim: profile.overview?.board.teamBadges.first { $0.id == badge }?.name.localized ?? "")
                }
            },
            wear: { presents in Task { await wear(presents) } })
    }

    /// 立刻穿上 (Tracy 2026-11-12: take me there to choose, don't save it): 衣橱 trying the letter's
    /// pieces on, nothing saved until the member saves it there; the badge board when it gave
    /// only a badge, where the member wears it or not. A piece the member already had another way
    /// (unlocked by training, so the team's give_reward left it as it was) is theirs all the same:
    /// one still waiting on 商店街 is claimed (领取) first, so 衣橱 can put it on. The profile is
    /// read again only when the one on hand misses a present; a piece still not theirs after
    /// that is left out.
    private func wear(_ presents: [TeamPresent]) async {
        let pieces = presents.compactMap { present -> String? in
            if case .piece(let id) = present { id } else { nil }
        }
        if !presents.allSatisfy({ profile.holds($0) }) { await profile.reload() }
        let held = pieces.filter { profile.holds(.piece($0)) }
        guard !held.isEmpty else { return open(.badges) }
        for piece in held where profile.unclaimed.contains(piece) { await profile.claim(piece) }
        // 衣橱 puts on only what the member owns: a claim that didn't save leaves that piece off.
        showCloset(trying: held, readAgain: false)
    }
}

extension MeModel {
    /// Whether the profile on hand already has `present`: a badge on the board, a piece among
    /// the team's and coaches' gifts, claimed, or unlocked and waiting on 商店街.
    fileprivate func holds(_ present: TeamPresent) -> Bool {
        switch present {
        case .badge(let id): overview?.board.teamBadges.contains { $0.id == id } ?? false
        case .piece(let id):
            (overview?.gifts.contains(id) ?? false) || (overview?.claimed.contains(id) ?? false)
                || unclaimed.contains(id)
        }
    }
}

/// A piece as the wardrobe draws it, or a team badge's ticket from the member's badge board,
/// which is read again when the profile on hand doesn't have it yet.
private struct TeamPresentPicture: View {
    let present: TeamPresent
    let profile: MeModel

    var body: some View {
        switch present {
        case .piece(let piece):
            WardrobePicture(.piece, item: piece)
        case .badge(let id):
            Group {
                if let badge = profile.overview?.board.teamBadges.first(where: { $0.id == id }) {
                    TitleBadgeView(
                        shape: TitleBadgeView.Shape.ticket.rawValue, colour: badge.id, tone: badge.tone,
                        glyph: badge.glyph, size: 56)
                } else {
                    Color.clear
                }
            }
            .task { if !profile.holds(present) { await profile.reload() } }
        }
    }
}
