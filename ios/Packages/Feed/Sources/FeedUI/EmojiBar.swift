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
                    EmojiGrid(model: model) { emoji in
                        grid = nil
                        model.react(.pick(emoji), on: post, from: CGPoint(x: button.midX, y: button.midY))
                    }
                    .position(gridCenter(over: button, in: proxy))
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                } else {
                    EmojiBar(model: model, mine: post.reactions.kind(of: model.viewer)) { index in
                        guard let from = model.slotCenter(index) else { return }
                        model.react(.pick(EmojiBar.common[index]), on: post, from: from)
                    } more: {
                        withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { grid = post.id }
                    }
                    .fixedSize()
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
                WhoPanel(model: model, reactions: post.reactions)
                    .position(panelCenter(at: proxy[who.bounds], for: post.reactions, in: proxy))
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
    private func panelCenter(at row: CGRect, for reactions: Responses<Emoji>, in proxy: GeometryProxy) -> CGPoint {
        let width = WhoPanel.width
        let height = WhoPanel.height(for: reactions)
        let midX = max(min(row.minX, proxy.size.width - Space.pageMargin - width), Space.pageMargin) + width / 2
        let below = row.maxY + Space.xxs + height / 2
        let fitsBelow = below + height / 2 < proxy.size.height - proxy.safeAreaInsets.bottom
        return CGPoint(x: midX, y: fitsBelow ? below : row.minY - Space.xxs - height / 2)
    }
}

/// The six quick emoji and ＋, which opens our emoji grid for any other: a glass capsule over the
/// card. Mine sits on a grey circle; picking it again takes it back. While a finger holds and
/// slides along it, the slot under the finger grows.
struct EmojiBar: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let mine: Emoji?
    let pick: (Int) -> Void
    let more: () -> Void
    @State private var shown = false

    static let height: Double = 52
    private static let emojiSize: Double = 28
    static let inset = Space.xxs
    /// Six slots and ＋, each a tap target wide, inside the capsule's ends.
    static var width: Double { Double(common.count + 1) * Sizing.minimumTapTarget + 2 * inset }
    private static let hoverScale: Double = 1.3
    private static let hoverRise: Double = 6
    private static let slotStagger: Double = 0.015

    /// The bar's emoji, in the approved order.
    static let common = Emoji.quick

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.common.enumerated()), id: \.element) { index, emoji in
                let hovered = model.hovering == index
                Button {
                    pick(index)
                } label: {
                    Text(verbatim: emoji.text)
                        .font(.system(size: Self.emojiSize))
                        .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                        .background {
                            if emoji == mine { Circle().fill(Color(role: .bgSubtle, in: theme)) }
                        }
                        .scaleEffect(hovered ? Self.hoverScale : (shown || reduceMotion ? 1 : 0.4))
                        .offset(y: hovered ? -Self.hoverRise : 0)
                        .opacity(shown || reduceMotion ? 1 : 0)
                        .animation(
                            .wildcard(Motion.sheet, reduceMotion: reduceMotion).delay(Double(index) * Self.slotStagger),
                            value: shown
                        )
                        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: hovered)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(emoji == mine ? .isSelected : [])
                .accessibilityIdentifier("feed.emoji.\(emoji.text)")
            }
            Button(action: more) {
                Image(systemName: "plus")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                    .background(Color(role: .bgSubtle, in: theme), in: Circle())
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("更多表情", bundle: .module))
            .accessibilityIdentifier("feed.emoji.more")
        }
        .padding(.horizontal, Self.inset)
        .frame(height: Self.height)
        .glassEffect(.regular, in: Capsule())
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("选一个回应", bundle: .module))
        .accessibilityIdentifier("feed.emojiBar")
    }
}

#endif
