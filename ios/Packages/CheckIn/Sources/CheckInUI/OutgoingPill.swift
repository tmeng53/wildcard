#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 打卡's spot while my post goes out behind the scene (the approved async-post prototype): the
/// same accent capsule, reading 正在发送… round a ring that fills as the photos go up, then
/// 已发出 with 查看, which opens the post, or 没网，连上自动发 when it has to wait.
struct OutgoingPill: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let outgoing: TodayModel.Outgoing
    let progress: Double?
    let open: (CheckIn) -> Void
    let dismiss: () -> Void

    /// The badge's inset from the capsule's edge, so it sits as a circle inside it.
    private static let badgeInset: Double = Space.xs
    private static let badge: Double = Sizing.compactControl

    var body: some View {
        Button(action: tap) {
            HStack(spacing: Space.s) {
                badge
                    .frame(width: Self.badge, height: Self.badge)
                    .accessibilityHidden(true)
                title
                if case .sent = outgoing {
                    Text(copy: "查看", bundle: .module)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: tone.fill, in: theme))
                        .padding(.horizontal, Space.s)
                        .frame(height: Sizing.smallTag + Space.xs)
                        .background(Color(role: tone.onFill, in: theme), in: Capsule())
                }
            }
            // The capsule's own inset is `Space.l`; the badge sits closer to its edge.
            .padding(.leading, Self.badgeInset - Space.l)
            .padding(.trailing, isSent ? Self.badgeInset - Space.l : 0)
        }
        .buttonStyle(PrimaryButtonStyle())
        .allowsHitTesting(!isSending)
        .accessibilityIdentifier("today.outgoing")
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: outgoing)
    }

    private var isSending: Bool { if case .sending = outgoing { true } else { false } }
    private var isSent: Bool { if case .sent = outgoing { true } else { false } }

    @ViewBuilder
    private var title: some View {
        switch outgoing {
        case .sending: Text(copy: "正在发送…", bundle: .module)
        case .sent: Text(copy: "已发出", bundle: .module)
        case .waiting: Text(copy: "没网，连上自动发", bundle: .module)
        }
    }

    @ViewBuilder
    private var badge: some View {
        ZStack {
            Circle().fill(.foreground.opacity(0.18))
            switch outgoing {
            case .sending:
                Circle()
                    .trim(from: 0, to: max(progress ?? 0, Self.startingSliver))
                    .stroke(.foreground, style: StrokeStyle(lineWidth: Sizing.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(Sizing.ringWidth / 2)
                    .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: progress)
                Image(systemName: "arrow.up")
                    .font(.system(size: Sizing.smallIcon, weight: .bold))
            case .sent:
                Image(systemName: "checkmark")
                    .font(.system(size: Sizing.smallIcon, weight: .bold))
            case .waiting:
                Image(systemName: "wifi.slash")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
            }
        }
    }

    /// A sliver of the ring shows from the start, so it reads as on its way.
    private static let startingSliver = 0.06

    private func tap() {
        switch outgoing {
        case .sending: break
        case .sent(let saved): open(saved)
        case .waiting: dismiss()
        }
    }
}
#endif
