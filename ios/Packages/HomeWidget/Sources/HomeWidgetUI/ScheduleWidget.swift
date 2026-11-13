#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import SportsUI
import SwiftUI

/// 本周出赛表, picked in place of 我的一周 or 小队今天 from the widget's 编辑小组件 (Tracy,
/// 2026-11-13, boards E and F): the 出赛表 poster's grid in the squad's scene colour, the squad's
/// coach standing behind today's challenge (今日挑战: what to do, then its amount large), or an
/// empty spot for one while the squad has none. Small: today's sport and the challenge. Medium:
/// the week's number (W8) over the coach, and the whole week as sport icons, done days ticked.
/// The coach never speaks here. It fills the widget edge to edge, so the extension turns the
/// system's margins off for it, and wears `ScheduleWidget.Backdrop` as its container background.
/// A tap opens 出赛表 (`WidgetLink.schedule`).
public struct ScheduleWidget: View {
    public enum Size: Sendable {
        case small
        case medium
    }

    @Environment(\.sceneTheme) private var theme
    private let board: WidgetBoard
    private let size: Size

    public init(board: WidgetBoard, size: Size) {
        self.board = board
        self.size = size
    }

    public var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(onScene)
        // A picture with a fixed layout, like the poster it comes from.
        .dynamicTypeSize(.large)
    }

    private var onScene: Color { Color(role: .fgOnAccent, in: theme) }

    // MARK: Small

    /// Today stacked over the card; on a phone whose widgets are shorter (148 points), today's
    /// sport beside its disc, so a two-line challenge still fits.
    private var small: some View {
        ViewThatFits(in: .vertical) {
            smallLayout(stacked: true)
            smallLayout(stacked: false)
        }
    }

    private func smallLayout(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.xs) {
                if let today = board.planToday {
                    todayBlock(today, stacked: stacked)
                        .frame(maxWidth: Metrics.smallToday, alignment: .leading)
                }
                Spacer(minLength: 0)
                weekCount(stacked: true)
            }
            Spacer(minLength: 0)
            ScheduleChallengeCard(board: board, compact: true)
        }
        .padding(.horizontal, Metrics.edge)
        .padding(.top, Metrics.edge)
        .padding(.bottom, Metrics.cardInset)
        .background(alignment: .bottomTrailing) {
            ScheduleCoach(coach: board.coach, height: stacked ? Metrics.smallCoach : Metrics.shortCoach)
                .padding(.trailing, Space.xs)
                .padding(.bottom, Metrics.smallCoachLift)
        }
    }

    /// 今天 · 周四, today's sport in a disc, and its name under it or beside it.
    private func todayBlock(_ today: WidgetBoard.PlanDay, stacked: Bool) -> some View {
        let name = caption(today)
            .typeStyle(TypeRamp.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        return VStack(alignment: .leading, spacing: Space.xxs) {
            (Text(copy: "今天", bundle: .module) + Text(verbatim: " · ") + WeekdayName.full(today.weekday))
                .typeStyle(TypeRamp.caption)
                .opacity(0.8)
            if stacked {
                todayDisc(today)
                name
            } else {
                HStack(spacing: Space.xs) {
                    todayDisc(today)
                    name
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Today's sport on a white disc, ticked once I trained; the moon on a rest day.
    private func todayDisc(_ today: WidgetBoard.PlanDay) -> some View {
        Group {
            switch today.status {
            case .restDay:
                Image(systemName: "moon.fill")
                    .font(.system(size: Metrics.todayGlyph * 0.85, weight: .semibold))
                    .frame(width: Metrics.todayDisc, height: Metrics.todayDisc)
                    .background(onScene.opacity(Metrics.wash), in: Circle())
            case .disclaimer:
                Text(copy: "假", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .frame(width: Metrics.todayDisc, height: Metrics.todayDisc)
                    .background(onScene.opacity(Metrics.wash), in: Circle())
            case .trained, .open:
                Image(systemName: Self.symbol(today))
                    .font(.system(size: Metrics.todayGlyph, weight: .semibold))
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                    .frame(width: Metrics.todayDisc, height: Metrics.todayDisc)
                    .background(Color(role: .bgCanvas, in: theme), in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        if today.status == .trained { tick(size: Metrics.tick).offset(x: 3, y: 3) }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// The scene-coloured tick on a done day's disc.
    private func tick(size: Double) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundStyle(onScene)
            .frame(width: size, height: size)
            .background(Color(role: .bgAccent, in: theme), in: Circle())
            .overlay { Circle().stroke(Color(role: .bgCanvas, in: theme), lineWidth: Sizing.hairline * 3) }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 0) {
            weekNumber
                .frame(width: Metrics.mediumLeft, alignment: .topLeading)
                .padding(.leading, Metrics.edge)
                .padding(.top, Space.xs)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(copy: "本周出赛表", bundle: .module)
                        .typeStyle(TypeRamp.captionEmphasis)
                        .opacity(0.85)
                    Spacer(minLength: Space.xs)
                    weekCount(stacked: false)
                }
                .padding(.trailing, Space.xxs)
                days
                    .padding(.top, Space.xxs)
                Spacer(minLength: Space.xxs)
                ScheduleChallengeCard(board: board, compact: false)
            }
            .padding(.top, Metrics.edge - Space.xxs)
            .padding(.bottom, Metrics.cardInset)
            .padding(.trailing, Metrics.cardInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottomLeading) {
            ScheduleCoach(coach: board.coach, height: Metrics.mediumCoach)
                .padding(.leading, Metrics.mediumCoachLeft)
                .offset(y: Metrics.mediumCoachSink)
        }
    }

    /// W8: the squad's week, as the poster writes it.
    @ViewBuilder private var weekNumber: some View {
        if let number = board.weekNumber {
            Text(verbatim: "W\(number)")
                .typeStyle(TypeRamp.scoreWeek)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(Text(copy: "第 \(number) 周", bundle: .module))
        }
    }

    /// 本周 2/5: days I trained over the days I planned.
    private func weekCount(stacked: Bool) -> some View {
        let count = Text(verbatim: "\(board.mine.trainedDays)/\(board.mine.plannedDays)")
            .typeStyle(stacked ? TypeRamp.scoreInline : TypeRamp.scoreSmall)
        let label = Text(copy: "本周", bundle: .module)
            .typeStyle(TypeRamp.caption)
            .opacity(0.8)
        return Group {
            if stacked {
                VStack(alignment: .trailing, spacing: 0) {
                    label
                    count
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    label
                    count
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(copy: "本周 \(board.mine.trainedDays)/\(board.mine.plannedDays) 天", bundle: .module))
    }

    /// The week, Monday to Sunday: each day's label over its sport icon, today's label bold.
    private var days: some View {
        HStack(spacing: 0) {
            ForEach(board.plan, id: \.weekday) { day in
                VStack(spacing: Space.xxs) {
                    WeekdayName.short(day.weekday)
                        .typeStyle(day.isToday ? TypeRamp.captionEmphasis : TypeRamp.caption)
                        .opacity(day.isToday ? 1 : 0.65)
                    dayCell(day)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WeekdayName.full(day.weekday) + Text(verbatim: " ") + caption(day))
            }
        }
    }

    /// A day as an icon: done white with a tick, today white with its sport, a planned day ringed
    /// with its sport, a rest day its moon, a 请假条 day 假.
    @ViewBuilder private func dayCell(_ day: WidgetBoard.PlanDay) -> some View {
        let side = Metrics.day
        switch day.status {
        case .trained:
            Image(systemName: "checkmark")
                .font(.system(size: side * 0.45, weight: .heavy))
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .frame(width: side, height: side)
                .background(Color(role: .bgCanvas, in: theme), in: Circle())
        case .disclaimer:
            Text(copy: "假", bundle: .module)
                .typeStyle(TypeRamp.tabSelected)
                .opacity(0.8)
                .frame(width: side, height: side)
                .background(onScene.opacity(Metrics.wash), in: Circle())
        case .restDay:
            Image(systemName: "moon.fill")
                .font(.system(size: side * 0.4))
                .opacity(day.isToday ? 1 : 0.55)
                .frame(width: side, height: side)
                .background(onScene.opacity(day.isToday ? Metrics.wash : 0), in: Circle())
        case .open where day.isToday:
            Image(systemName: Self.symbol(day))
                .font(.system(size: side * 0.5, weight: .semibold))
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .frame(width: side, height: side)
                .background(Color(role: .bgCanvas, in: theme), in: Circle())
        case .open:
            Image(systemName: Self.symbol(day))
                .font(.system(size: side * 0.45, weight: .medium))
                .opacity(0.85)
                .frame(width: side, height: side)
                .overlay { Circle().stroke(onScene.opacity(0.4), lineWidth: Sizing.hairline * 3) }
        }
    }

    // MARK: Days

    /// A day's sport icon; a training day with no sport gets the runner, as on the squad card.
    private static func symbol(_ day: WidgetBoard.PlanDay) -> String {
        day.activity?.symbol ?? "figure.run"
    }

    /// What a day is for: its sport, else 休息, 请假 or 训练.
    private func caption(_ day: WidgetBoard.PlanDay) -> Text {
        if let activity = day.activity { return activity.cardName }
        switch day.status {
        case .restDay: return Text(copy: "休息", bundle: .module)
        case .disclaimer: return Text(copy: "请假", bundle: .module)
        case .trained, .open: return Text(copy: "训练", bundle: .module)
        }
    }

    /// Sizes that belong to this widget only, for a widget 170 points tall.
    private enum Metrics {
        static let edge: Double = 14
        static let cardInset: Double = 8
        static let todayDisc: Double = 28
        static let todayGlyph: Double = 15
        static let tick: Double = 14
        static let day: Double = 25
        static let wash = ScheduleCoach.wash
        /// The medium widget's left column, where W8 and the coach stand.
        static let mediumLeft: Double = 90
        static let mediumCoach: Double = 150
        static let mediumCoachLeft: Double = 4
        /// How far the medium coach's feet go below the widget's edge, so it stands behind the card.
        static let mediumCoachSink: Double = 18
        /// The small widget's today, clear of the coach on its right.
        static let smallToday: Double = 96
        static let smallCoach: Double = 104
        /// The small coach on a shorter widget, clear of 本周 over it.
        static let shortCoach: Double = 86
        /// The small coach's feet stand behind the card.
        static let smallCoachLift: Double = 18
    }
}

extension ScheduleWidget {
    /// The scene the widget wears: the squad's this week, the gym when it couldn't be read.
    public static func scene(of board: WidgetBoard) -> SceneTheme {
        board.scene.flatMap { SceneTheme(rawValue: $0.rawValue) } ?? .gym
    }
}
#endif
