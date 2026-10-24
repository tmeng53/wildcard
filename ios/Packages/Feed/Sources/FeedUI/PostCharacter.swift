#if os(iOS)
import AvatarUI
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The author's character at the card's left, full height. It holds still, drawn once, so a
/// feed of cards costs nothing to scroll; when someone reacts it plays the move, redrawing
/// every frame only for as long as the move lasts. On my own post, a teammate's reaction that
/// arrived shows in a small bubble over my character, with their head and emoji.
struct PostCharacter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost

    var body: some View {
        if let player = model.player(for: post) {
            let played = model.played[post.id]
            figure(player, moving: played != nil && !reduceMotion)
                .frame(height: Sizing.characterFull)
                .anchorPreference(key: FeedAnchors.self, value: .bounds) { FeedAnchors.Value(heads: [post.id: $0]) }
                .overlay(alignment: .top) {
                    if let bubble = model.bubbles[post.id] {
                        ArrivalBubble(model: model, arrival: bubble.arrival)
                            .alignmentGuide(.top) { $0[.bottom] }
                            .transition(.speech(reduceMotion: reduceMotion))
                            .task(id: bubble.count) {
                                let hold = (played.map { $0.until.timeIntervalSinceNow } ?? 0) + FeedModel.bubbleHold
                                try? await Task.sleep(for: .seconds(max(hold, FeedModel.bubbleHold)))
                                withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) {
                                    model.bubbleShown(post.id, count: bubble.count)
                                }
                            }
                    }
                }
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

/// Who reacted to my post and with what: their head and emoji in a white bubble with a tail.
private struct ArrivalBubble: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let arrival: Arrival

    private static let head: Double = 22
    private static let emojiSize: Double = 18
    private static let tail = CGSize(width: 12, height: 6)

    var body: some View {
        HStack(spacing: Space.xxs) {
            Face(player: model.head(of: arrival.member), size: Self.head)
            Text(verbatim: arrival.emoji.text).font(.system(size: Self.emojiSize))
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.xxs)
        .background(Color(role: .bgCanvas, in: theme), in: Capsule())
        .padding(.bottom, Self.tail.height)
        .background(alignment: .bottom) {
            BubbleTail()
                .fill(Color(role: .bgCanvas, in: theme))
                .frame(width: Self.tail.width, height: Self.tail.height)
        }
    }
}

/// The bubble's tail, pointing down at the character.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
#endif
