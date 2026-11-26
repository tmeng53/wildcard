#if os(iOS)
import AvatarUI
import CheckInUI
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The author's whole character at the card's left, head to feet, looping what the post is about while
/// the card is on screen (the feed's cards are lazy, so only the visible ones draw): a 练了's
/// sport, a meal being eaten, a 请假条 held up. With Reduce Motion it holds still. On my own post,
/// a teammate's reaction that arrived shows in a small bubble over my character, with their head
/// and emoji.
struct PostCharacter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost
    /// How wide the character stands; it is 4 points tall for every 3 wide, as the rig's canvas.
    let width: Double

    /// The part of the rig's canvas drawn: all of it, with 40 points more either side.
    private static let room = CGRect(x: -40, y: 0, width: 320, height: 320)

    var body: some View {
        if let player = model.player(for: post) {
            let played = model.played[post.id]
            figure(player, moving: (played != nil || model.loops(post)) && !reduceMotion)
                .overlay {
                    if model.holdsSign(post) {
                        GeometryReader { proxy in
                            // On the rig's 240 × 320 canvas, centred at y 249, as on the home.
                            let scale = proxy.size.height / 320
                            SignCard(scale: scale).position(x: proxy.size.width / 2, y: 249 * scale)
                        }
                    }
                }
                // The rig's 240 × 320 canvas at `width`, drawn with room either side so a move
                // that swings a prop past the canvas (快走's cup) shows whole, over the padding.
                .frame(width: width * Self.room.width / 240, height: width * Self.room.height / 240)
                .frame(width: width, height: width * 320 / 240)
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
            CharacterView(player: player, crop: Self.room)
        } else {
            let frame = player.restFrame
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.room)
                .aspectRatio(Self.room.width / Self.room.height, contentMode: .fit)
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
            MemberHead(player: model.head(of: arrival.member), size: Self.head)
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
