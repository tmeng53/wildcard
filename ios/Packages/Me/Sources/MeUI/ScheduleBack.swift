#if os(iOS)
import CharacterEditorUI
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
/// bottom their newest badges and how many, which open the badge board, beside 穿搭 and the first
/// pieces they wear, which open what they wear (Tracy, 2026-11-10, A).
struct ScheduleBack: View {
    let face: PlayerCardFace
    let schedule: MateSchedule
    let openBoard: () -> Void
    let openOutfit: () -> Void
    @Environment(\.sceneTheme) private var theme

    // From the approved design.
    private static let rowHeight: Double = 38
    private static let todayShade = 0.1
    private static let smallBadge: Double = 22
    /// The line between 徽章 and 穿搭, as faint as a hairline on ink.
    private static let divider = 0.3
    /// Badges shown beside 徽章; the board has the rest.
    private static let badgesShown = 2

    private var ink: Color { Color(role: .fgOnInk, in: theme) }
    private var muted: Color { Color(role: .fgOnInkMuted, in: theme) }

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
            HStack(spacing: 0) {
                badges
                Rectangle()
                    .fill(Color(role: .fgOnInkMuted, in: theme).opacity(Self.divider))
                    .frame(width: 1)
                    .padding(.vertical, Space.s)
                    .accessibilityHidden(true)
                outfit
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .top) { Hairline(on: .ink) }
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
            Text(copy: "出赛表", bundle: .module)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            if let count = face.week {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    Score(count: count.trainedDays, goal: count.plannedDays, size: .card, onInk: true)
                    Text(copy: "本周", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let isToday = index == schedule.todayIndex
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
            Text(copy: "饮食小目标", bundle: .module)
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
                Text(copy: "徽章", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(ink)
                    .fixedSize()
                HStack(spacing: Space.xxs) {
                    ForEach(face.board.titles.prefix(Self.badgesShown)) { title in
                        TitleBadgeView(
                            shape: title.badge.shape, colour: title.badge.colour, tone: title.badge.tone,
                            glyph: title.badge.glyph,
                            size: Self.smallBadge)
                    }
                }
                Spacer(minLength: Space.xxs)
                Text(verbatim: "\(face.board.count)")
                    .typeStyle(TypeRamp.scoreCaption)
                    .foregroundStyle(muted)
                    .monospacedDigit()
                    // A count of 10 or more stays on one line; the badges give way first.
                    .fixedSize()
                chevron
            }
            .padding(.horizontal, Space.xxs)
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("me.cardBadges")
    }

    /// 穿搭 and the first pieces they wear, opening what they wear.
    private var outfit: some View {
        Button(action: openOutfit) {
            HStack(spacing: Space.xs) {
                Text(copy: "穿搭", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(ink)
                    .fixedSize()
                WornOutfitPeek(outfit: face.character.outfit)
                Spacer(minLength: Space.xxs)
                chevron
            }
            .padding(.leading, Space.s)
            .padding(.trailing, Space.xxs)
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("me.cardOutfitRow")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: Sizing.smallIcon * 0.8, weight: .semibold))
            .foregroundStyle(muted)
            .accessibilityHidden(true)
    }
}
#endif
