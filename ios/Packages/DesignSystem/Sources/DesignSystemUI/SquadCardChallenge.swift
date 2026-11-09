#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// My week: what I trained, my count against my plan (the folded capsule says it), and Monday to
/// Sunday, each day with what it holds. No calories or body numbers.
public struct MyWeek: Sendable, Hashable {
    public let done: Int
    public let planned: Int
    /// Monday first, seven days.
    public let days: [WeekDayStatus]
    /// Today's index in `days`, if this is the current week.
    public let today: Int?
    /// Monday first, seven days: what each day shows once picked; empty for a week whose days
    /// can't be picked.
    public let details: [WeekDayDetail]
    /// Today's challenge from the coach, once accepted: the squad page's last row.
    public let challenge: WeekChallenge?

    public init(
        done: Int, planned: Int, days: [WeekDayStatus], today: Int?, details: [WeekDayDetail],
        challenge: WeekChallenge? = nil
    ) {
        self.done = done
        self.planned = planned
        self.days = days
        self.today = today
        self.details = details
        self.challenge = challenge
    }
}

/// The day's challenge the member accepted from the coach (Tracy, 2026-11-08): what to do, who
/// set it, and 我完成了 until it is done.
public struct WeekChallenge: Sendable, Hashable {
    /// What to do with its amount: 「拉伸 5 分钟」.
    public let title: String
    /// Who set it: 「毛头 · 今日挑战」.
    public let byline: String
    public let isDone: Bool

    public init(title: String, byline: String, isDone: Bool) {
        (self.title, self.byline, self.isDone) = (title, byline, isDone)
    }
}

/// The squad page's last row, past a hairline: the flag in a graphite disc, the challenge and
/// who set it, then 我完成了 (graphite) or 「✓ 已完成」.
struct ChallengeRow: View {
    @Environment(\.sceneTheme) private var theme
    let challenge: WeekChallenge
    let complete: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.s) {
            Rectangle()
                .fill(Color(role: .borderDefault, in: theme))
                .frame(height: Sizing.hairline)
            HStack(spacing: Space.s) {
                Image(systemName: "flag.fill")
                    .font(.system(size: Sizing.smallIcon * 0.75, weight: .semibold))
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                    .frame(width: Sizing.smallIcon * 1.6, height: Sizing.smallIcon * 1.6)
                    .background(Color(role: .bgBrand, in: theme), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: challenge.title)
                        .typeStyle(TypeRamp.body)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                    Text(verbatim: challenge.byline)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if challenge.isDone {
                    Label {
                        Text("已完成", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityIdentifier("squadcard.challenge.done")
                } else if let complete {
                    Button(action: complete) { Text("我完成了", bundle: .module) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("squadcard.challenge.complete")
                }
            }
        }
        .padding(.top, Space.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squadcard.challenge")
    }
}
#endif
