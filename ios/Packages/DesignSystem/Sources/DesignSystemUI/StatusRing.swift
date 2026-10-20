#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Where someone stands today, as their status ring shows it.
public enum RingStatus: Sendable, Hashable {
    /// Nothing yet today.
    case open
    /// Checked in: 练了 or a 请假条.
    case done
    /// A rest day in the week's plan.
    case restDay
}

/// An avatar's ring for today, like Apple Fitness: a grey track, drawn closed in the scene's ring
/// color from 12 o'clock once the person checks in (练了 or a 请假条); a rest day keeps the grey
/// ring and gets a small moon. When the ring turns `done` while on screen it draws itself in, fast
/// then slow, and the avatar pops once. Only the ring of the person holding the phone plays
/// haptics (`playsHaptics`): light ticks while it draws, one heavy hit as it closes, which is the
/// check-in's hit, so a screen showing it plays no other. With Reduce Motion on, the closed ring
/// just appears, with the hit.
public struct StatusRing<Avatar: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let status: RingStatus
    private let avatarSize: Double
    private let playsHaptics: Bool
    private let avatar: Avatar
    @State private var drawn: Double
    @State private var pops = 0
    /// Times the ring has turned `done` while on screen; its haptics play for each.
    @State private var draws = 0
    @State private var ticks = 0
    @State private var closes = 0

    public init(
        status: RingStatus, avatarSize: Double = Sizing.characterHead, playsHaptics: Bool = false,
        @ViewBuilder avatar: () -> Avatar
    ) {
        self.status = status
        self.avatarSize = avatarSize
        self.playsHaptics = playsHaptics
        self.avatar = avatar()
        _drawn = State(initialValue: status == .done ? 1 : 0)
    }

    private var diameter: Double { avatarSize + 2 * (Sizing.ringGap + Sizing.ringWidth) }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color(role: .borderDefault, in: theme), lineWidth: Sizing.ringWidth)
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(
                    Color(role: .ring, in: theme),
                    style: StrokeStyle(lineWidth: Sizing.ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            avatar
                .frame(width: avatarSize, height: avatarSize)
                .background(Color(role: .bgSubtle, in: theme))
                .clipShape(Circle())
                .keyframeAnimator(initialValue: 1.0, trigger: pops) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1, duration: Motion.ringFill)
                        SpringKeyframe(
                            Motion.ringPopScale, duration: 0.12,
                            spring: Spring(
                                response: Motion.press.response, dampingRatio: Motion.press.dampingFraction))
                        SpringKeyframe(
                            1, duration: Motion.celebrate.response,
                            spring: Spring(
                                response: Motion.celebrate.response, dampingRatio: Motion.celebrate.dampingFraction))
                    }
                }
        }
        // The stroke is centered on the circle's edge, so inset it by half its width.
        .padding(Sizing.ringWidth / 2)
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottomTrailing) {
            if status == .restDay {
                Moon(size: diameter * 0.42)
                    .offset(x: Sizing.ringWidth, y: Sizing.ringWidth)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: status) { _, newStatus in
            guard newStatus == .done else {
                drawn = 0
                return
            }
            draws += 1
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: Motion.ringFill)) { drawn = 1 }
                pops += 1
            }
        }
        // Keyed by the status too, so a ring that opens again mid-draw cancels its haptics.
        .task(id: [AnyHashable(status), AnyHashable(draws)]) {
            guard playsHaptics, status == .done, draws > 0 else { return }
            await playHaptics()
        }
        .haptic(.tick, trigger: ticks)
        .haptic(.checkIn, trigger: closes)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusLabel)
    }

    /// The ticks spread across the drawing, then the hit as the ring closes; with Reduce Motion,
    /// just the hit. Stops when the task is cancelled.
    @MainActor
    private func playHaptics() async {
        let step = Motion.ringFill / Double(Haptic.ringTicks + 1)
        for _ in 0..<(reduceMotion ? 0 : Haptic.ringTicks) {
            guard (try? await Task.sleep(for: .seconds(step))) != nil else { return }
            ticks += 1
        }
        if !reduceMotion {
            guard (try? await Task.sleep(for: .seconds(step))) != nil else { return }
        }
        closes += 1
    }

    private var statusLabel: Text {
        switch status {
        case .open: Text("还没打卡", bundle: .module)
        case .done: Text("打卡了", bundle: .module)
        case .restDay: Text("休息日", bundle: .module)
        }
    }
}

/// The small moon on a rest day's ring: white disc, muted moon.
private struct Moon: View {
    @Environment(\.sceneTheme) private var theme
    let size: Double

    var body: some View {
        Image(systemName: "moon.fill")
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .frame(width: size, height: size)
            .background(Color(role: .bgCanvas, in: theme), in: Circle())
            .accessibilityHidden(true)
    }
}
#endif
