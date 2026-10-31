#if os(iOS)
import Contracts
import DailyPushDomain
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The emoji bar over the push while it is open, over its post's smiley (under it near the
/// top): a tap anywhere else closes it. ＋ lays every emoji over the push's bottom instead.
struct EmojiBarLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: DailyPushModel

    var body: some View {
        GeometryReader { proxy in
            if let open = model.picking, let button = model.buttons[open] {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                let below = button.minY - Space.xs - EmojiBar.height < Space.xxl * 2
                if model.browsing {
                    EmojiPanel(mine: model.store.mine(on: open)) { emoji, point in
                        model.pick(emoji, on: open, from: point)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(Space.xs)
                    .transition(.move(edge: .bottom))
                } else {
                    EmojiBar(mine: model.store.mine(on: open)) { emoji, point in
                        model.pick(emoji, on: open, from: point)
                    } more: {
                        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.browsing = true }
                    }
                    .fixedSize()
                    .position(
                        x: max(
                            min(button.maxX, proxy.size.width - Space.xs) - EmojiBar.width / 2,
                            Space.xs + EmojiBar.width / 2),
                        y: below
                            ? button.maxY + Space.xxs + 2 + EmojiBar.height / 2
                            : button.minY - Space.xs - EmojiBar.height / 2
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

/// The six common emoji and ＋, as on 动态: a white capsule over the post. Mine is ringed;
/// picking it again takes it back.
private struct EmojiBar: View {
    let mine: Emoji?
    /// The emoji, and where it was in `DailyPushView.space`, for it to fly from.
    let pick: (Emoji, CGPoint) -> Void
    let more: () -> Void

    static let height: Double = 52
    private static let emojiSize: Double = 28
    private static let inset = Space.xxs
    static var width: Double { Double(Emoji.quick.count) * Sizing.minimumTapTarget + Sizing.compactControl + 4 * inset }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Emoji.quick, id: \.self) { emoji in
                EmojiButton(emoji: emoji, size: Self.emojiSize, selected: emoji == mine, pick: pick)
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
            }
            Button(action: more) {
                Image(systemName: "plus")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgMuted, in: .gym))
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                    .background(Color(role: .bgSubtle, in: .gym), in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, Self.inset)
            .accessibilityLabel(Text("更多表情", bundle: .module))
        }
        .padding(.horizontal, Self.inset)
        .frame(height: Self.height)
        .background(Color(role: .bgCanvas, in: .gym), in: Capsule())
        .overlay { Capsule().stroke(Color(role: .borderDefault, in: .gym), lineWidth: Sizing.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("选一个回应", bundle: .module))
        .accessibilityIdentifier("dailyPush.emojiBar")
    }
}

/// Every emoji 动态's ＋ offers, laid over the push's bottom, since a push has no keyboard.
private struct EmojiPanel: View {
    let mine: Emoji?
    let pick: (Emoji, CGPoint) -> Void

    private static let height: Double = 250
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 8)
    private static let cell: Double = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxs) {
                SectionLabel(Text("全部", bundle: .module))
                    .padding(.horizontal, Space.xs - 2)
                LazyVGrid(columns: Self.columns, spacing: 0) {
                    ForEach(Emoji.all, id: \.self) { emoji in
                        EmojiButton(emoji: emoji, size: Self.cell * 0.65, selected: emoji == mine, pick: pick)
                            .frame(height: Self.cell)
                    }
                }
            }
            .padding(.horizontal, Space.xxs)
        }
        .padding(.top, Space.s)
        .padding(.horizontal, Space.xs)
        .padding(.bottom, Space.xs)
        .frame(height: Self.height)
        .background(
            Color(role: .bgCanvas, in: .gym), in: RoundedRectangle(cornerRadius: Radius.card + 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card + 8, style: .continuous)
                .stroke(Color(role: .borderDefault, in: .gym), lineWidth: Sizing.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("全部表情", bundle: .module))
    }
}

/// One emoji to pick, which knows where it is so the emoji can fly from there.
private struct EmojiButton: View {
    let emoji: Emoji
    let size: Double
    let selected: Bool
    let pick: (Emoji, CGPoint) -> Void
    @State private var center = CGPoint.zero

    var body: some View {
        Button {
            pick(emoji, center)
        } label: {
            Text(verbatim: emoji.text)
                .font(.system(size: size))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        Circle()
                            .fill(Color(role: .bgSubtle, in: .gym))
                            .overlay {
                                Circle().stroke(Color(role: .fgDefault, in: .gym), lineWidth: Sizing.selectionStroke)
                            }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onGeometryChange(for: CGPoint.self) {
            let frame = $0.frame(in: .named(DailyPushView.space))
            return CGPoint(x: frame.midX, y: frame.midY)
        } action: { point in
            center = point
        }
        .accessibilityLabel(Text(verbatim: emoji.text))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("dailyPush.emoji.\(emoji.text)")
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
