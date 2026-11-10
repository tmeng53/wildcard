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

/// The day's challenge the member accepted from the coach (Tracy, 2026-11-08): what to do and
/// how much, who set it, and 我完成了 until it is done.
public struct WeekChallenge: Sendable, Hashable {
    /// What to do: 「拉伸」.
    public let title: String
    /// How much, in the coach's own unit: 「5」 and 「分钟」; either may be missing.
    public let amount: String?
    public let unit: String?
    /// Who set it: 「毛头 · 今日挑战」.
    public let byline: String
    public let isDone: Bool

    public init(title: String, amount: String? = nil, unit: String? = nil, byline: String, isDone: Bool) {
        (self.title, self.amount, self.unit, self.byline, self.isDone) = (title, amount, unit, byline, isDone)
    }

    /// The whole challenge in words, as VoiceOver reads it: 「拉伸 5 分钟」.
    public var spoken: String { [title, amount, unit].compactMap(\.self).joined(separator: " ") }
}

extension SquadCard {
    /// Today's challenge, the squad page's last row (`MyWeek.challenge`): the head of the coach
    /// who set it, and 我完成了.
    public func challenge<Head: View>(complete: @escaping () -> Void, @ViewBuilder coach: () -> Head) -> Self {
        var card = self
        card.challengeCoach = AnyView(coach())
        card.completeChallenge = complete
        return card
    }
}

/// The challenge row's sizes callers draw to.
public enum ChallengeRowLayout {
    /// The coach's head: a little taller than the two lines beside it, so the row keeps its height.
    public static let head: Double = 36
}

/// The squad page's last row, past a hairline (Tracy, 2026-11-10, design A): the head of the coach
/// who set it with a small flag at its foot, what to do with its amount in the scoreboard face,
/// who set it, then 我完成了 (graphite) or a quiet 已完成. Done, the flag turns into a check with
/// a success haptic (Tracy, 2026-11-09: a check, no stamp), the row's one check.
struct ChallengeRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let challenge: WeekChallenge
    /// The coach's head; without one, a graphite disc stands in.
    let coach: AnyView?
    let complete: (() -> Void)?

    /// The flag or check on the head's lower right, and the ring that cuts it from the head.
    private static let badge: Double = 16
    private static let badgeRing: Double = 2

    var body: some View {
        VStack(spacing: Space.s) {
            Rectangle()
                .fill(Color(role: .borderDefault, in: theme))
                .frame(height: Sizing.hairline)
            HStack(spacing: Space.s) {
                head
                VStack(alignment: .leading, spacing: 0) {
                    title
                    Text(verbatim: challenge.byline)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if challenge.isDone {
                    Text(copy: "已完成", bundle: .module)
                        .typeStyle(TypeRamp.calloutEmphasis)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .fixedSize()
                        .accessibilityIdentifier("squadcard.challenge.done")
                } else if let complete {
                    Button(action: complete) { Text(copy: "我完成了", bundle: .module) }
                        .buttonStyle(SecondaryButtonStyle())
                        .fixedSize()
                        .accessibilityIdentifier("squadcard.challenge.complete")
                }
            }
        }
        .padding(.top, Space.s)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: challenge.isDone)
        .haptic(.done, trigger: challenge.isDone) { wasDone, isDone in !wasDone && isDone }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squadcard.challenge")
    }

    /// What to do, then its amount in the scoreboard face and the unit small, on one baseline.
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            Text(verbatim: challenge.title)
                .typeStyle(TypeRamp.pick)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .layoutPriority(1)
            if let amount = challenge.amount {
                Text(verbatim: amount)
                    .typeStyle(TypeRamp.scoreSmall)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .padding(.leading, Space.xxs)
            }
            if let unit = challenge.unit {
                Text(verbatim: unit)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: challenge.spoken))
        .accessibilityIdentifier("squadcard.challenge.title")
    }

    private var head: some View {
        Group {
            if let coach {
                coach
            } else {
                Circle().fill(Color(role: .bgBrand, in: theme))
            }
        }
        .frame(width: ChallengeRowLayout.head, height: ChallengeRowLayout.head)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: challenge.isDone ? "checkmark" : "flag.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: Self.badge / 2, weight: .bold))
                .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                .frame(width: Self.badge, height: Self.badge)
                .background(Color(role: .bgBrand, in: theme), in: Circle())
                .padding(Self.badgeRing)
                .background(Color(role: .bgCanvas, in: theme), in: Circle())
                .offset(x: Self.badgeRing + 1, y: Self.badgeRing + 1)
        }
        .accessibilityHidden(true)
    }
}
#endif
