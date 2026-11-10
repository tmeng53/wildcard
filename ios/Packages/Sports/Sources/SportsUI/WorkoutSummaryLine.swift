#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A workout from Health in one line: 「跑步 32 分钟 · 5.2 公里」, the numbers in the scoreboard
/// face. 今天's Health card and the home screen widgets' 打卡 capsule both say it this way; the
/// caller sets the words' style.
public struct WorkoutSummaryLine: View {
    private let activity: Activity?
    private let minutes: WorkoutMinutes?
    private let summary: WorkoutSummary

    public init(activity: Activity?, minutes: WorkoutMinutes?, summary: WorkoutSummary) {
        self.activity = activity
        self.minutes = minutes
        self.summary = summary
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            (activity?.name ?? Text(copy: "运动", bundle: .module))
            if let minutes {
                Text(verbatim: "\(minutes.value)").typeStyle(TypeRamp.scoreSmall)
                Text(copy: "分钟", bundle: .module)
            }
            if let distance = ScoreCell.cells(of: summary).first(where: { $0.cell == .distance }) {
                Text(verbatim: "·")
                Text(verbatim: distance.value).typeStyle(TypeRamp.scoreSmall)
                distance.unit?.text
            }
        }
    }
}
#endif
