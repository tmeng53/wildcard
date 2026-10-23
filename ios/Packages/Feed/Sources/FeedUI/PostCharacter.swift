#if os(iOS)
import AvatarUI
import DesignSystem
import FeedDomain
import SwiftUI

/// The author's character at the card's left, full height. It holds still, drawn once, so a
/// feed of cards costs nothing to scroll; when a teammate reacts it plays the move, redrawing
/// every frame only for as long as the move lasts.
struct PostCharacter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost

    var body: some View {
        if let player = model.player(for: post) {
            let played = model.played[post.id]
            figure(player, moving: played != nil && !reduceMotion)
                .frame(height: Sizing.characterFull)
                .task(id: played?.count) {
                    guard let played else { return }
                    try? await Task.sleep(for: .seconds(max(played.until.timeIntervalSinceNow, 0)))
                    model.finished(post.id, count: played.count)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func figure(_ player: CharacterPlayer, moving: Bool) -> some View {
        if moving {
            CharacterView(player: player)
        } else {
            let frame = player.restFrame
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                .aspectRatio(frame.drawing.width / frame.drawing.height, contentMode: .fit)
        }
    }
}
#endif
