#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// My post going out behind the scene, told at the top of the screen in a `NoticeBanner` that
/// drops from the Dynamic Island (the approved motion mockup, 2026-11-24): 正在发送… round a
/// ring that fills as the photos go up, then, in the same capsule, 已发出 over the post's cover
/// with 查看, which opens the post, or 没网，连上自动发 when it has to wait. A swipe up puts it
/// away once it is no longer sending.
struct OutgoingBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    let open: (CheckIn) -> Void
    @State private var drag: Double = 0

    var body: some View {
        ZStack {
            if let outgoing = model.outgoing {
                banner(outgoing)
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.top, Self.top)
                    .offset(y: min(0, drag))
                    .contentShape(Rectangle())
                    .onTapGesture { tap(outgoing) }
                    .gesture(swipeAway)
                    .transition(transition)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("today.outgoing")
            }
        }
        .animation(.wildcard(Motion.notice, reduceMotion: reduceMotion), value: model.outgoing == nil)
    }

    private func banner(_ outgoing: TodayModel.Outgoing) -> some View {
        NoticeBanner(title(outgoing), action: action(outgoing)) {
            OutgoingBadge(outgoing: outgoing, progress: model.outgoingProgress, cover: model.outgoingCover)
        }
        // Sending, sent and waiting are one capsule changing its words in place.
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: outgoing)
    }

    private func title(_ outgoing: TodayModel.Outgoing) -> Text {
        switch outgoing {
        case .sending: Text(copy: "正在发送…", bundle: .module)
        case .sent: Text(copy: "已发出", bundle: .module)
        case .waiting: Text(copy: "没网，连上自动发", bundle: .module)
        }
    }

    private func action(_ outgoing: TodayModel.Outgoing) -> Text? {
        if case .sent = outgoing { Text(copy: "查看", bundle: .module) } else { nil }
    }

    /// From the top of the safe area, as a `NoticeBanner` drops in.
    private static let top: Double = 4
    /// How far up a swipe puts it away.
    private static let dismissDrag: Double = 16

    private var swipeAway: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { drag = 0 }
                if value.translation.height < -Self.dismissDrag { model.dismissOutgoing() }
            }
    }

    /// Out of the top of the screen, shrinking up towards the Dynamic Island, as every
    /// `NoticeBanner` does; a fade with Reduce Motion on.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.6, anchor: .top).combined(with: .offset(y: -40)).combined(with: .opacity)
    }

    private func tap(_ outgoing: TodayModel.Outgoing) {
        switch outgoing {
        case .sending: break
        case .sent(let saved):
            open(saved)
            model.dismissOutgoing()
        case .waiting: model.dismissOutgoing()
        }
    }
}

/// The banner's round icon: a ring filling round an arrow while the post goes up, then the post's
/// cover (a check where it has none), or no network while it waits.
private struct OutgoingBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let outgoing: TodayModel.Outgoing
    let progress: Double?
    let cover: PreparedPhoto?

    var body: some View {
        // Each state a face of its own, so the icon blurs from one into the next.
        Group {
            switch outgoing {
            case .sending:
                NoticeSymbol(systemImage: "arrow.up", tone: .brand)
                    .overlay { ring }
            case .sent:
                if let cover {
                    PhotoImage(photo: cover)
                } else {
                    NoticeSymbol(systemImage: "checkmark")
                }
            case .waiting:
                NoticeSymbol(systemImage: "wifi.slash", tone: .brand)
            }
        }
        .id(face)
        .transition(.blurReplace)
        .accessibilityHidden(true)
    }

    private var ring: some View {
        Circle()
            .trim(from: 0, to: max(progress ?? 0, Self.startingSliver))
            .stroke(Color(role: .fgOnBrand, in: .gym), style: StrokeStyle(lineWidth: Sizing.ringWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(Sizing.ringWidth)
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: progress)
    }

    private var face: Int {
        switch outgoing {
        case .sending: 0
        case .sent: 1
        case .waiting: 2
        }
    }

    /// A sliver of the ring shows from the start, so it reads as on its way.
    private static let startingSliver = 0.06
}
#endif
