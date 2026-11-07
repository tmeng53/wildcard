#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import HealthDomain
import SportsUI
import SwiftUI

/// The Liquid Glass card under the squad card while today has a workout in Apple Health not
/// posted yet (Tracy, 2026-11-06): the newest one's sport, minutes and distance, 打卡, which
/// opens a 训练 already filled from it, and an ✕ that puts the workout away from the card, as a
/// tip's ✕ does (Tracy, 2026-11-07); 打卡 › 训练 still offers it.
struct HealthHomeCard: View {
    /// The card while there is a workout to offer and the scene is in hand: not while a check-in
    /// is being written or the squad is dropping in.
    struct Offer: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let model: TodayModel

        var body: some View {
            if let workout = model.workoutToPost, model.step == .scene, model.arrival == nil {
                HealthHomeCard(workout: workout) {
                    model.pick(.trained, workout: workout)
                } dismiss: {
                    withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.putAway(workout) }
                }
                .transition(.opacity)
            }
        }
    }

    @Environment(\.sceneTheme) private var theme
    let workout: ImportedWorkout
    let post: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "heart.fill")
                .font(.system(size: Self.heart))
                .foregroundStyle(Color(role: .fgDanger, in: theme))
                .accessibilityHidden(true)
            summary
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.health.summary")
            Button(action: post) {
                Text(copy: "打卡", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .padding(.horizontal, Space.s)
                    .frame(height: Self.button)
                    .background(Color(role: .bgInk, in: theme), in: Capsule())
                    .frame(minHeight: Sizing.minimumTapTarget)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("today.health.post")
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: Self.close, weight: .semibold))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(copy: "收起", bundle: .module))
            .accessibilityIdentifier("today.health.dismiss")
        }
        .padding(.leading, Space.s)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .padding(.horizontal, Space.pageMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.health")
    }

    /// 「跑步 32 分钟 · 5.2 公里」, the numbers in the scoreboard face.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            (workout.activity?.name ?? Text(copy: "运动", bundle: .module))
            if let minutes = workout.minutes {
                Text(verbatim: "\(minutes.value)").typeStyle(TypeRamp.scoreSmall)
                Text(copy: "分钟", bundle: .module)
            }
            if let distance = ScoreCell.cells(of: workout.workout.summary).first(where: { $0.cell == .distance }) {
                Text(verbatim: "·")
                Text(verbatim: distance.value).typeStyle(TypeRamp.scoreSmall)
                distance.unit?.text
            }
        }
        .typeStyle(TypeRamp.calloutEmphasis)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
    }

    private static let heart: Double = 12
    private static let button: Double = 34
    private static let close: Double = 13
    private static let corner: Double = 22
}
#endif
