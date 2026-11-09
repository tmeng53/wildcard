#if canImport(SwiftUI)
import Contracts
import DesignSystem
import DesignSystemUI
import HealthDomain
import SportsUI
import SwiftUI

/// The workout Health just synced, at a widget's foot, as 今天's Health card says it: the heart,
/// 「跑步 32 分钟 · 5.2 公里」 and 打卡, which posts it there and then. Widgets can't draw Liquid
/// Glass, so it is the card's shape on the subtle fill with a hairline; the home screen's tinted
/// and clear styles turn it to glass themselves. The distance goes first, then the minutes, when
/// the line is too long for the widget.
public struct WorkoutCapsule<Post: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let workout: ImportedWorkout
    private let post: Post

    public init(workout: ImportedWorkout, @ViewBuilder post: () -> Post) {
        self.workout = workout
        self.post = post()
    }

    public var body: some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: "heart.fill")
                .font(.system(size: WidgetMetrics.heart))
                .foregroundStyle(Color(role: .fgDanger, in: theme))
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                line(minutes: workout.minutes, summary: workout.workout.summary)
                line(minutes: workout.minutes, summary: WorkoutSummary())
                line(minutes: nil, summary: WorkoutSummary())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("widget.workout")
            post
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.xxs)
        .frame(height: WidgetMetrics.capsule)
        .background(Color(role: .bgSubtle, in: theme), in: Capsule())
        .overlay { Capsule().stroke(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline) }
    }

    private func line(minutes: WorkoutMinutes?, summary: WorkoutSummary) -> some View {
        WorkoutSummaryLine(activity: workout.activity, minutes: minutes, summary: summary)
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(1)
            .fixedSize()
    }
}

/// 打卡 inside the capsule: the extension wraps it in the App Intent that posts the workout, and
/// the app's `-widgets` preview shows it as it is.
public struct PostWorkoutLabel: View {
    @Environment(\.sceneTheme) private var theme

    public init() {}

    public var body: some View {
        Text("打卡", bundle: .module)
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgOnInk, in: theme))
            .padding(.horizontal, Space.s)
            .frame(height: WidgetMetrics.capsuleButton)
            .background(Color(role: .bgInk, in: theme), in: Capsule())
            .accessibilityIdentifier("widget.postWorkout")
    }
}
#endif
