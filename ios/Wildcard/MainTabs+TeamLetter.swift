import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystemUI
import MeDomain
import SportsUI
import SwiftUI

/// The team's letter on 今天 (感谢信, Tracy 2026-11-11): what the team gave, drawn from the
/// wardrobe and the member's badge board, and 立刻穿上, which wears it all and opens 衣橱 wearing it,
/// as a coach's gift's 立刻穿上 and 去衣橱看看 do.
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

    /// 立刻穿上: the badge worn on the member's card and the pieces in their slots, saved side by
    /// side, then 衣橱 trying the first piece on (the badge board when it gave no piece). Only what
    /// the member holds, from the profile the letter's tiles were drawn from, never read again
    /// (each read of it is ten calls); 今天 is read again after, without holding up the page.
    private func wear(_ presents: [TeamPresent]) async {
        // Read again only when the profile on hand misses a present, as one read before the
        // team's give_reward would.
        if !presents.allSatisfy { profile.holds($0) } { await profile.reload() }
        let badges = Set(profile.overview?.board.teamBadges.map(\.id) ?? [])
        let held = Set(profile.overview?.gifts ?? [])
        let badge = presents.lazy.compactMap { present -> String? in
            if case .badge(let id) = present, badges.contains(id) { id } else { nil }
        }.first
        let pieces = presents.compactMap { present -> String? in
            if case .piece(let id) = present, held.contains(id) { id } else { nil }
        }
        let equipping = Task { if let badge { _ = await profile.equip(.teamBadge(badge)) } }
        await wardrobe.wearHeld(pieces)
        await equipping.value
        if let piece = pieces.first { showCloset(trying: piece, readAgain: false) } else { open(.badges) }
        Task { await today.load() }
    }
}

extension MeModel {
    /// Whether the profile on hand already has `present`: a badge on the board, a piece among
    /// the team's and coaches' gifts.
    fileprivate func holds(_ present: TeamPresent) -> Bool {
        switch present {
        case .badge(let id): overview?.board.teamBadges.contains { $0.id == id } ?? false
        case .piece(let id): overview?.gifts.contains(id) ?? false
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
