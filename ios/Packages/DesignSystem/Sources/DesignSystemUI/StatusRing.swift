#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Where someone stands today, as their status ring shows it.
public enum RingStatus: Sendable, Hashable {
    /// Nothing yet today.
    case open
    /// Checked in.
    case done
    /// Excused today (请假条).
    case excused
}

/// An avatar's ring for today, like Apple Fitness: a grey track, drawn closed in the scene's ring
/// color from 12 o'clock once the person checks in; a 请假条 keeps the grey ring and gets a small
/// moon. When the ring turns `done` while on screen it draws itself in, fast then slow, and the
/// avatar pops once. With Reduce Motion on, the closed ring just appears.
public struct StatusRing<Avatar: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let status: RingStatus
    private let avatarSize: Double
    private let avatar: Avatar
    @State private var drawn: Double
    @State private var pops = 0

    public init(status: RingStatus, avatarSize: Double = Sizing.characterHead, @ViewBuilder avatar: () -> Avatar) {
        self.status = status
        self.avatarSize = avatarSize
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
                        SpringKeyframe(Motion.ringPopScale, duration: 0.12, spring: .snappy)
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
            if status == .excused {
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
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: Motion.ringFill)) { drawn = 1 }
                pops += 1
            }
        }
        .sensoryFeedback(.success, trigger: pops)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusLabel)
    }

    private var statusLabel: Text {
        switch status {
        case .open: Text("还没打卡", bundle: .module)
        case .done: Text("打卡了", bundle: .module)
        case .excused: Text("请假了", bundle: .module)
        }
    }
}

/// The small moon on an excused ring: white disc, muted moon.
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
