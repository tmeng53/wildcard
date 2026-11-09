#if os(iOS)
import Contracts
import DailyPushDomain
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The shared reaction bar over the push while it is open, over its post's smiley (under it near
/// the top): a tap anywhere else closes it. ＋ lays the shared emoji picker over the push's bottom
/// instead, without a search, since a push has no keyboard.
struct EmojiBarLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: DailyPushModel
    /// Where the open bar and panel are in `DailyPushView.space`, for the emoji to fly from.
    @State private var bar: CGRect?
    @State private var panel: CGRect?

    private static let panelHeight: Double = 250

    var body: some View {
        GeometryReader { proxy in
            if let open = model.picking, let button = model.buttons[open] {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                let height = ReactionBarMetrics.height
                let width = ReactionBarMetrics.width(count: Emoji.quick.count)
                let below = button.minY - Space.xs - height < Space.xxl * 2
                if model.browsing {
                    EmojiPicker(
                        recent: [], all: Emoji.all, text: \.text, mine: model.store.mine(on: open),
                        identifier: "dailyPush.emoji"
                    ) { emoji in
                        let from =
                            panel.map { CGPoint(x: $0.midX, y: $0.minY) } ?? CGPoint(x: button.midX, y: button.midY)
                        model.pick(emoji, on: open, from: from)
                    }
                    .frame(height: Self.panelHeight)
                    .accessibilityAction(.escape) { close() }
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(DailyPushView.space))
                    } action: {
                        panel = $0
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(Space.xs)
                    .transition(.move(edge: .bottom))
                } else {
                    ReactionBar(
                        Emoji.quick, text: \.text, mine: model.store.mine(on: open), identifier: "dailyPush.emoji"
                    ) { index in
                        let from =
                            bar.map { ReactionBarMetrics.slotCenter(index, in: $0) }
                            ?? CGPoint(x: button.midX, y: button.midY)
                        model.pick(Emoji.quick[index], on: open, from: from)
                    } more: {
                        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.browsing = true }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("dailyPush.emojiBar")
                    // VoiceOver can't tap outside: its two-finger scrub closes it instead.
                    .accessibilityAction(.escape) { close() }
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(DailyPushView.space))
                    } action: {
                        bar = $0
                    }
                    .position(
                        x: max(min(button.maxX, proxy.size.width - Space.xs) - width / 2, Space.xs + width / 2),
                        y: below ? button.maxY + Space.xxs + 2 + height / 2 : button.minY - Space.xs - height / 2
                    )
                    .transition(
                        .scale(scale: 0.4, anchor: below ? .topTrailing : .bottomTrailing).combined(with: .opacity))
                }
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.picking)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.browsing)
    }

    private func close() {
        withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) {
            model.picking = nil
            model.browsing = false
        }
    }
}

/// The emoji flying from the bar to its author: up in an arc, a little bigger at the top, then
/// down onto the head, in 0.45 seconds. With Reduce Motion it doesn't fly; the bubble still shows.
struct FlightLayer: View {
    let flight: DailyPushModel.Flight?
    let reduceMotion: Bool

    private static let size: Double = 28
    private static let rise: Double = 60

    var body: some View {
        if let flight, !reduceMotion {
            let mid = CGPoint(
                x: (flight.from.x + flight.target.x) / 2, y: min(flight.from.y, flight.target.y) - Self.rise)
            let start = Point(at: flight.from, scale: 1)
            Text(verbatim: flight.emoji.text)
                .font(.system(size: Self.size))
                .keyframeAnimator(initialValue: start, trigger: flight.count) { emoji, point in
                    emoji.scaleEffect(point.scale).position(x: point.across, y: point.down)
                } keyframes: { _ in
                    let half = DailyPushModel.flightTime / 2
                    KeyframeTrack(\.across) {
                        CubicKeyframe(mid.x, duration: half)
                        CubicKeyframe(flight.target.x, duration: half)
                    }
                    KeyframeTrack(\.down) {
                        CubicKeyframe(mid.y, duration: half)
                        CubicKeyframe(flight.target.y, duration: half)
                    }
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.15, duration: half)
                        CubicKeyframe(0.8, duration: half)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    struct Point {
        var across: Double
        var down: Double
        var scale: Double

        init(at point: CGPoint, scale: Double) {
            (across, down, self.scale) = (point.x, point.y, scale)
        }
    }
}
#endif
