#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// One day: its circle over its name. Today's name is ink and heavier; the picked day's sits in
/// an ink capsule.
struct DayCircle: View {
    @Environment(\.sceneTheme) private var theme
    let status: WeekDayStatus
    let isToday: Bool
    let isPicked: Bool
    let weekday: Int

    var body: some View {
        VStack(spacing: Space.xxs) {
            circle
                .frame(width: SquadCardMetrics.day, height: SquadCardMetrics.day)
            Self.name(weekday)
                .typeStyle(isToday || isPicked ? TypeRamp.tabSelected : TypeRamp.tab)
                .foregroundStyle(Color(role: isPicked ? .bgCanvas : isToday ? .fgDefault : .fgMuted, in: theme))
                .frame(minWidth: SquadCardMetrics.pick, minHeight: SquadCardMetrics.pick - 2)
                .background {
                    if isPicked { Capsule().fill(Color(role: .fgDefault, in: theme)) }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.name(weekday))
        .accessibilityValue(value)
    }

    @ViewBuilder private var circle: some View {
        switch status {
        case .trained(let symbol):
            Image(systemName: symbol ?? "checkmark")
                .font(.system(size: SquadCardMetrics.dayGlyph, weight: .bold))
                .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgAccent, in: theme), in: Circle())
                .overlay(alignment: .bottomTrailing) { if symbol != nil { checkBadge } }
        case .excused:
            Text("假", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
        case .restDay:
            Image(systemName: "moon.fill")
                .font(.system(size: SquadCardMetrics.dayGlyph * 0.85))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
        case .planned(let symbol):
            ring.overlay {
                Image(systemName: symbol)
                    .font(.system(size: SquadCardMetrics.dayGlyph, weight: .semibold))
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
            }
        case .open: ring
        }
    }

    /// The small check that tells a done day from a planned one when both show the sport.
    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: SquadCardMetrics.badgeGlyph, weight: .heavy))
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .frame(width: SquadCardMetrics.badge, height: SquadCardMetrics.badge)
            .background(Color(role: .fgOnAccent, in: theme), in: Circle())
            .offset(x: 3, y: 3)
    }

    private var ring: some View {
        Circle()
            .strokeBorder(
                Color(role: isToday ? .fgDefault : .borderDefault, in: theme),
                lineWidth: isToday ? SquadCardMetrics.todayStroke : Sizing.selectionStroke)
    }

    private var value: Text {
        switch status {
        case .trained: Text("练了", bundle: .module)
        case .excused: Text("请假", bundle: .module)
        case .restDay: Text("休息日", bundle: .module)
        case .open where isToday, .planned where isToday: Text("今天", bundle: .module)
        case .open, .planned: Text("还没练", bundle: .module)
        }
    }

    /// 周一 to 周日, for the picked day's line.
    static func fullName(_ weekday: Int) -> Text {
        switch weekday {
        case 0: Text("周一", bundle: .module)
        case 1: Text("周二", bundle: .module)
        case 2: Text("周三", bundle: .module)
        case 3: Text("周四", bundle: .module)
        case 4: Text("周五", bundle: .module)
        case 5: Text("周六", bundle: .module)
        default: Text("周日", bundle: .module)
        }
    }

    static func name(_ weekday: Int) -> Text {
        switch weekday {
        case 0: Text("一", bundle: .module)
        case 1: Text("二", bundle: .module)
        case 2: Text("三", bundle: .module)
        case 3: Text("四", bundle: .module)
        case 4: Text("五", bundle: .module)
        case 5: Text("六", bundle: .module)
        default: Text("日", bundle: .module)
        }
    }
}
/// The picked day's line under the calendar: 今天 · 跑步 32 分钟, with its meals on the right.
struct DayLine: View {
    @Environment(\.sceneTheme) private var theme
    let detail: WeekDayDetail
    let weekday: Int
    let isToday: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Group {
                    if isToday { Text("今天", bundle: .module) } else { DayCircle.fullName(weekday) }
                }
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text(verbatim: " · ")
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text(verbatim: detail.line)
                    .typeStyle(detail.isPlan ? TypeRamp.footnote : TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: detail.isPlan ? .fgMuted : .fgDefault, in: theme))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let meals = detail.meals {
                Count(label: Text("健康餐", bundle: .module), value: meals.healthy)
                Count(label: Text("放纵餐", bundle: .module), value: meals.cheat)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("squadcard.dayLine")
    }
}

/// A count beside its label: 健康餐 3.
struct Count: View {
    @Environment(\.sceneTheme) private var theme
    let label: Text
    let value: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            label
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            Score(count: value, size: .small)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
