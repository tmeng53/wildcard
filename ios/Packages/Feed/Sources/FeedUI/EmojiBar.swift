#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Where a post's floating piece belongs: its button for the emoji bar, its row for who reacted.
struct FeedAnchor {
    let post: CheckInID
    let bounds: Anchor<CGRect>
}

/// Where the feed's floating pieces go: the open emoji bar's button, the row whose who-reacted
/// panel is open, and each author's character on screen, for emoji to fly to.
struct FeedAnchors: PreferenceKey {
    struct Value {
        var bar: FeedAnchor?
        var who: FeedAnchor?
        var heads: [CheckInID: Anchor<CGRect>] = [:]
    }

    static var defaultValue: Value { Value() }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        value.bar = value.bar ?? next.bar
        value.who = value.who ?? next.who
        value.heads.merge(next.heads) { $1 }
    }
}

/// What floats over the feed: the emoji bar or our emoji grid over a post's button, who reacted
/// over its row, and emoji on their way to a head. While the bar, the grid or the panel is open,
/// a tap anywhere else closes it. Everything here is in `FeedView.space`.
struct FeedLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let bar: FeedAnchor?
    let who: FeedAnchor?
    let heads: [CheckInID: Anchor<CGRect>]
    @State private var grid: CheckInID?

    var body: some View {
        GeometryReader { proxy in
            if bar != nil || who != nil || grid != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
            }
            if let bar, let post = model.store.post(bar.post) {
                let button = proxy[bar.bounds]
                if grid == post.id {
                    EmojiPicker(
                        recent: model.recent, all: Emoji.all, search: EmojiCatalog.matching, text: \.text,
                        identifier: "feed.emoji"
                    ) { emoji in
                        grid = nil
                        model.react(.pick(emoji), on: post, from: CGPoint(x: button.midX, y: button.midY))
                    }
                    .frame(width: EmojiGrid.size.width, height: EmojiGrid.size.height)
                    .accessibilityIdentifier("feed.emojiGrid")
                    .accessibilityAction(.escape) { close() }
                    .position(gridCenter(over: button, in: proxy))
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                } else {
                    ReactionBar(
                        EmojiBar.common, text: \.text, mine: post.reactions.kind(of: model.viewer),
                        hovered: model.hovering, identifier: "feed.emoji"
                    ) { index in
                        guard let from = model.slotCenter(index), let emoji = Emoji.quick(at: index) else { return }
                        model.react(.pick(emoji), on: post, from: from)
                    } more: {
                        withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { grid = post.id }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("feed.emojiBar")
                    // VoiceOver can't tap outside: its two-finger scrub closes it instead.
                    .accessibilityAction(.escape) { close() }
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(FeedView.space))
                    } action: { frame in
                        model.barFrame = frame
                    }
                    .position(barCenter(over: button, in: proxy))
                    .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            if let who, let post = model.store.post(who.post) {
                let coach = model.coachReply(on: post.id)
                WhoPanel(model: model, reactions: post.reactions, coach: coach)
                    .accessibilityAction(.escape) { close() }
                    .position(panelCenter(at: proxy[who.bounds], for: post.reactions, coach: coach, in: proxy))
                    .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
            }
            ForEach(model.flights) { flight in
                if let head = heads[flight.post].map({ proxy[$0] }) {
                    FlyingEmoji(flight: flight, to: CGPoint(x: head.midX, y: head.minY + head.height * 0.22))
                }
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: bar?.post)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: who?.post)
        .onChange(of: bar?.post) { _, post in
            if post == nil { grid = nil }
        }
    }

    private func close() {
        withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) {
            grid = nil
            model.closeBar()
            model.listing = nil
        }
    }

    /// Above the row with its right edge on my button; below it when that would reach the top.
    private func barCenter(over button: CGRect, in proxy: GeometryProxy) -> CGPoint {
        let width = EmojiBar.width
        let midX = max(min(button.maxX, proxy.size.width - Space.pageMargin) - width / 2, Space.pageMargin + width / 2)
        let above = button.minY - Space.xs - EmojiBar.height / 2
        let fitsAbove = above - EmojiBar.height / 2 > proxy.safeAreaInsets.top + Space.xs
        return CGPoint(x: midX, y: fitsAbove ? above : button.maxY + Space.xs + EmojiBar.height / 2)
    }

    private func gridCenter(over button: CGRect, in proxy: GeometryProxy) -> CGPoint {
        let size = EmojiGrid.size
        let midX = max(
            min(button.maxX, proxy.size.width - Space.pageMargin) - size.width / 2, Space.pageMargin + size.width / 2)
        let above = button.minY - Space.xs - size.height / 2
        let fitsAbove = above - size.height / 2 > proxy.safeAreaInsets.top + Space.xs
        return CGPoint(x: midX, y: fitsAbove ? above : button.maxY + Space.xs + size.height / 2)
    }

    /// Right there at the row: under it when there's room, else over it.
    private func panelCenter(
        at row: CGRect, for reactions: Responses<Emoji>, coach: CoachReply?, in proxy: GeometryProxy
    ) -> CGPoint {
        let width = WhoPanel.width
        let height = WhoPanel.height(for: reactions, coach: coach)
        let midX = max(min(row.minX, proxy.size.width - Space.pageMargin - width), Space.pageMargin) + width / 2
        let below = row.maxY + Space.xxs + height / 2
        let fitsBelow = below + height / 2 < proxy.size.height - proxy.safeAreaInsets.bottom
        return CGPoint(x: midX, y: fitsBelow ? below : row.minY - Space.xxs - height / 2)
    }
}

/// The bar's emoji, in the approved order.
enum EmojiBar {
    static var common: [Emoji] { Emoji.quick }
    static let height = ReactionBarMetrics.height
    static var width: Double { ReactionBarMetrics.width(count: common.count) }
}

#endif
