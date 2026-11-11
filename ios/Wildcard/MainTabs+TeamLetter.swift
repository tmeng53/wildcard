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

    /// 立刻穿上: the badge worn on the member's card, each piece in its slot, then 衣橱 trying the
    /// first piece on (the badge board when it gave no piece).
    private func wear(_ presents: [TeamPresent]) async {
        var pieces: [String] = []
        for present in presents {
            switch present {
            case .badge(let badge): await profile.equip(.teamBadge(badge))
            case .piece(let piece): pieces.append(piece)
            }
        }
        for piece in pieces { await wardrobe.wear(piece) }
        await today.load()
        open(pieces.first.map { .wardrobe(piece: $0) } ?? .badges)
    }
}

/// A piece as the wardrobe draws it, or a team badge's ticket from the member's badge board,
/// which is read first when 我 hasn't been yet.
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
            .task { if profile.overview == nil { await profile.reload() } }
        }
    }
}
