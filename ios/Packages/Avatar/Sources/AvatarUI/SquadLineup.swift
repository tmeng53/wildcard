#if canImport(SwiftUI)
import AvatarDomain
import Foundation
import SwiftUI

/// 排队入场: the squad along the edge of a screen, each character playing its own idle. Up to
/// five stand in a row; more walk through in a looping queue (`Lineup`). It knows nothing of
/// the screen it sits on, so any screen can use it (the 战报's last page, the invite page):
/// pass the members' players, in the order they should stand or walk. Its height sets the
/// figures' size (96 in the design); it fills the width it is given and clips what walks past
/// the edges. With Reduce Motion on, everyone stands still at rest.
public struct SquadLineup: View {
    let players: [CharacterPlayer]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(players: [CharacterPlayer]) {
        self.players = players
    }

    public var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion || players.isEmpty)) { timeline in
                LineupFrame(
                    players: players, size: geometry.size, date: timeline.date,
                    time: timeline.date.timeIntervalSinceReferenceDate, still: reduceMotion)
            }
        }
        .clipped()
        // Decoration: the screen around it says who is in the squad.
        .accessibilityHidden(true)
    }
}

/// One frame of the lineup: where `Lineup` puts each member at `time`, in the pose its player
/// has at `date`, or everyone standing still (`Lineup.rest`) when `still`.
struct LineupFrame: View {
    let players: [CharacterPlayer]
    let size: CGSize
    let date: Date
    let time: Double
    let still: Bool

    /// The design's figure height, which `Lineup`'s lengths are given at.
    static let designHeight = 96.0

    var body: some View {
        let lineup = Lineup(count: players.count, width: size.width).scaled(by: size.height / Self.designHeight)
        let spots = still ? lineup.rest : lineup.spots(at: time)
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(players, spots).enumerated()), id: \.offset) { item in
                let (player, spot) = item.element
                let frame = still ? player.restFrame : player.frame(at: date)
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                    .frame(width: lineup.figureWidth, height: size.height)
                    .offset(x: spot.left, y: still ? 0 : -spot.lift)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
#endif
