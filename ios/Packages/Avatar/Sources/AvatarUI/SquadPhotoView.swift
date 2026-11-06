#if canImport(SwiftUI)
import AvatarDomain
import Foundation
import SwiftUI

/// The squad posed for a group photo in the box it is given (`SquadPhoto`): everyone whole,
/// in one row or two, each character playing its own idle. With Reduce Motion on, everyone
/// stands still at rest.
public struct SquadPhotoView: View {
    let players: [CharacterPlayer]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(players: [CharacterPlayer]) {
        self.players = players
    }

    public var body: some View {
        GeometryReader { geometry in
            let photo = SquadPhoto(count: players.count, width: geometry.size.width, height: geometry.size.height)
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion || players.isEmpty)) { timeline in
                ZStack(alignment: .topLeading) {
                    ForEach(photo.spots, id: \.member) { spot in
                        let player = players[spot.member]
                        let frame = reduceMotion ? player.restFrame : player.frame(at: timeline.date)
                        CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                            .frame(width: photo.figureWidth, height: photo.figureHeight)
                            .offset(x: spot.left, y: spot.top)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        // Decoration: the screen around it says who is in the squad.
        .accessibilityHidden(true)
    }
}
#endif
