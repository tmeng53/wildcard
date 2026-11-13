#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import SportsUI
import SwiftUI

/// 本周出赛表, what my week's plan says, picked in place of 我的一周 or 小队今天 from the widget's
/// 编辑小组件: small, today's sport large over the next days; medium, the whole week with each
/// day's sport under it, done days ticked, as the squad card's calendar draws them. A tap opens
/// 出赛表 (`WidgetLink.schedule`).
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Small

    /// The days after today the small widget lists under it.
    private static let daysAhead = 3

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(Text(copy: "本周出赛表", bundle: .module))
            if let today = board.plan.first(where: \.isToday) {
                Group {
                    Text(copy: "今天", bundle: .module) + Text(verbatim: " · ") + WeekdayName.full(today.weekday)
                }
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .padding(.top, Space.xs)
                todayLine(today)
            }
            Spacer(minLength: Space.xxs)
            ForEach(board.planAhead(Self.daysAhead + 1).dropFirst(), id: \.weekday) { day in
                HStack {
                    WeekdayName.full(day.weekday)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                    Spacer(minLength: Space.xxs)
                    caption(day)
                        .typeStyle(TypeRamp.captionEmphasis)
                        .foregroundStyle(Color(role: isRest(day) ? .fgSubtle : .fgDefault, in: theme))
                }
                .typeStyle(TypeRamp.caption)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Today's sport, large, with a tick once I trained.
    private func todayLine(_ today: WidgetBoard.PlanDay) -> some View {
        HStack(spacing: Space.xxs) {
            if let activity = today.activity {
                Image(systemName: activity.symbol)
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
            } else if today.status == .restDay {
                Image(systemName: "moon.fill")
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
            }
            caption(today)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if today.status == .trained {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                    .accessibilityLabel(Text(copy: "今天练了", bundle: .module))
            }
        }
        .typeStyle(TypeRamp.cardTitle)
        .padding(.top, Space.xxs / 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(Text(copy: "本周出赛表", bundle: .module))
                Spacer(minLength: Space.xs)
                Text(copy: "\(board.mine.trainedDays)/\(board.mine.plannedDays) 天", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            Spacer(minLength: 0)
            WeekDayRow(
                days: board.plan.map(Self.status), today: board.week.today, size: .regular,
                captions: board.plan.map(caption))
            Spacer(minLength: 0)
        }
    }

    // MARK: Days

    /// A day as the squad card's calendar draws it: a training day still to do shows its sport.
    private static func status(_ day: WidgetBoard.PlanDay) -> WeekDayStatus {
        switch day.status {
        case .trained: .trained(symbol: day.activity?.symbol)
        case .disclaimer: .excused
        case .restDay: .restDay
        // A training day without a sport gets a generic icon, as on the card.
        case .open: .planned(symbol: day.activity?.symbol ?? "figure.run")
        }
    }

    private func isRest(_ day: WidgetBoard.PlanDay) -> Bool { day.status == .restDay }

    /// What a day is for: its sport, else 休息, 请假 or 训练.
    private func caption(_ day: WidgetBoard.PlanDay) -> Text {
        if let activity = day.activity { return activity.cardName }
        switch day.status {
        case .restDay: return Text(copy: "休息", bundle: .module)
        case .disclaimer: return Text(copy: "请假", bundle: .module)
        case .trained, .open: return Text(copy: "训练", bundle: .module)
        }
    }
}
#endif
