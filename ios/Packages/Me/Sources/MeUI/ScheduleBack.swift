#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import ScheduleDomain
import ScheduleUI
import SwiftUI

/// A squadmate's card turned over (Tracy, 2026-11-07, design E1): their name and number, W6 出赛表
/// with 本周 x/y, a row a day of this week (the day's sport in a disc, its name, a tick for a day
/// trained, 请假 for a 请假条; today shaded), their 饮食小目标 when they set any, and along the
/// bottom their newest badges and how many, which open the badge board.
struct ScheduleBack: View {
    let face: PlayerCardFace
    let schedule: MateSchedule
    let openBoard: () -> Void
    @Environment(\.sceneTheme) private var theme

    // From the approved design.
    private static let rowHeight: Double = 38
    private static let todayShade = 0.1
    private static let smallBadge: Double = 26
    /// Badges shown beside 徽章; the board has the rest.
    private static let badgesShown = 2

    private var ink: Color { Color(role: .fgOnInk, in: theme) }
    private var muted: Color { Color(role: .fgOnInkMuted, in: theme) }

    /// Their today's place in the week, Monday 0, on their calendar.
    private var todayIndex: Int? {
        schedule.todayIndex(else: LocalDay(at: Date(), in: .current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            week
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xs)
                .overlay(alignment: .bottom) { Hairline(on: .ink) }
            VStack(spacing: 0) {
                ForEach(0..<WeeklyPlan.dayCount, id: \.self) { index in row(index) }
            }
            .padding(.top, Space.xxs)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("me.cardSchedule")
            if !schedule.fuel.isEmpty { fuel }
            Spacer(minLength: Space.xs)
            badges
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(face.character.nickname)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: Space.s)
            if let number = face.number {
                Text(verbatim: "#\(number.text)")
                    .typeStyle(TypeRamp.scoreSmall)
                    .foregroundStyle(muted)
                    .monospacedDigit()
            }
        }
    }

    private var week: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: "W\(schedule.weekNumber)")
                .typeStyle(TypeRamp.scoreWeek)
                .foregroundStyle(ink)
                .fixedSize()
            Text("出赛表", bundle: .module)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            if let count = face.week {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    Score(count: count.trainedDays, goal: count.plannedDays, size: .card, onInk: true)
                    Text("本周", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let isToday = index == todayIndex
        let face = schedule.marks[index].face(of: schedule.days[index])
        let dayRow = ScheduleDayRow(
            day: schedule.weekStart.adding(days: index), isToday: isToday,
            shown: face.shown, mark: face.mark,
            colors: .init(
                ink: ink, onInk: Color(role: .bgInk, in: theme), markDisc: ink,
                markGlyph: Color(role: .bgInk, in: theme)),
            marksAtEnd: true)
        return
            dayRow
            .padding(.horizontal, Space.xs)
            .frame(height: Self.rowHeight)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                        .fill(ink.opacity(Self.todayShade))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayRow.accessibilityText)
    }

    /// 饮食小目标 and the goals, on one line.
    private var fuel: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text("饮食小目标", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(muted)
                .fixedSize()
            fuelLine
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Space.xxs)
        .padding(.top, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("me.cardFuel")
    }

    /// The goals in the order picked, as the poster joins them.
    private var fuelLine: Text {
        let goals = schedule.fuel.map(\.label)
        return goals.dropFirst().reduce(goals.first ?? Text(verbatim: "")) { $0 + Text(verbatim: " · ") + $1 }
    }

    /// 徽章, the newest badges and how many, opening the board.
    private var badges: some View {
        Button(action: openBoard) {
            HStack(spacing: Space.xs) {
                Text("徽章", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(ink)
                ForEach(face.board.titles.prefix(Self.badgesShown)) { title in
                    TitleBadgeView(
                        shape: title.badge.shape, colour: title.badge.colour, tone: title.badge.tone,
                        glyph: title.badge.glyph,
                        size: Self.smallBadge)
                }
                Spacer(minLength: Space.xs)
                Text(verbatim: "\(face.board.count)")
                    .typeStyle(TypeRamp.scoreCaption)
                    .foregroundStyle(muted)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.smallIcon * 0.8, weight: .semibold))
                    .foregroundStyle(muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.xxs)
            .padding(.vertical, Space.s)
            .overlay(alignment: .top) { Hairline(on: .ink) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("me.cardBadges")
    }
}
#endif
