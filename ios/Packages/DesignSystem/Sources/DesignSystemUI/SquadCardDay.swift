#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// One day: its circle over its name. Today's name is ink and heavier; the picked day's sits in
/// an ink capsule. `.compact`, in the folded squad capsule, draws it smaller and names today 今天;
/// `.tiny`, in the small home screen widget, smaller still, with today's weekday in ink.
struct DayCircle: View {
    enum Size {
        case regular
        case compact
        case tiny
    }

    @Environment(\.sceneTheme) private var theme
    let status: WeekDayStatus
    let isToday: Bool
    let isPicked: Bool
    let weekday: Int
    var size = Size.regular

    var body: some View {
        VStack(spacing: size == .regular ? Space.xxs : SquadCardMetrics.compactDayGap) {
            circle
                .frame(width: diameter, height: diameter)
            label
                .typeStyle(isToday || isPicked ? TypeRamp.tabSelected : TypeRamp.tab)
                .foregroundStyle(Color(role: isPicked ? .bgCanvas : isToday ? .fgDefault : .fgMuted, in: theme))
                .frame(
                    minWidth: size == .tiny ? nil : SquadCardMetrics.pick,
                    minHeight: size == .tiny ? nil : SquadCardMetrics.pick - 2
                )
                .background {
                    if isPicked { Capsule().fill(Color(role: .fgDefault, in: theme)) }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeekdayName.short(weekday))
        .accessibilityValue(value)
    }

    private var diameter: Double {
        switch size {
        case .regular: SquadCardMetrics.day
        case .compact: SquadCardMetrics.compactDay
        case .tiny: SquadCardMetrics.tinyDay
        }
    }

    /// How much smaller a compact day draws its glyphs.
    private var scale: Double { diameter / SquadCardMetrics.day }

    private var label: Text {
        size == .compact && isToday ? Text(copy: "今天", bundle: .module) : WeekdayName.short(weekday)
    }

    @ViewBuilder private var circle: some View {
        switch status {
        case .trained(let symbol):
            Image(systemName: symbol ?? "checkmark")
                .font(.system(size: SquadCardMetrics.dayGlyph * scale, weight: .bold))
                .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgAccent, in: theme), in: Circle())
                .overlay(alignment: .bottomTrailing) { if symbol != nil { checkBadge } }
        case .excused:
            Text(copy: "假", bundle: .module)
                .typeStyle(size == .regular ? TypeRamp.footnoteEmphasis : TypeRamp.tabSelected)
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
        case .restDay:
            Image(systemName: "moon.fill")
                .font(.system(size: SquadCardMetrics.dayGlyph * 0.85 * scale))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
        case .planned(let symbol):
            ring.overlay {
                Image(systemName: symbol)
                    .font(.system(size: SquadCardMetrics.dayGlyph * scale, weight: .semibold))
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
            }
        case .open: ring
        }
    }

    /// The small check that tells a done day from a planned one when both show the sport.
    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: SquadCardMetrics.badgeGlyph * scale, weight: .heavy))
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .frame(width: SquadCardMetrics.badge * scale, height: SquadCardMetrics.badge * scale)
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
        case .trained: Text(copy: "训练", bundle: .module)
        case .excused: Text(copy: "请假", bundle: .module)
        case .restDay: Text(copy: "休息日", bundle: .module)
        case .open where isToday, .planned where isToday: Text(copy: "今天", bundle: .module)
        case .open, .planned: Text(copy: "还没练", bundle: .module)
        }
    }
}

/// The picked day's line under the calendar: 今天 · 跑步 32 分钟, with its meals on the right. A day
/// with more than one session shows the first and how many more (「玩耍 60 分钟 +2 项」, Tracy
/// 2026-11-09), so the line never runs into the meals.
struct DayLine: View {
    @Environment(\.sceneTheme) private var theme
    let detail: WeekDayDetail
    let weekday: Int
    let isToday: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Group {
                    if isToday { Text(copy: "今天", bundle: .module) } else { WeekdayName.full(weekday) }
                    Text(verbatim: " · ")
                }
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .layoutPriority(1)
                Text(verbatim: detail.lines.first ?? "")
                    .typeStyle(detail.isPlan ? TypeRamp.footnote : TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: detail.isPlan ? .fgMuted : .fgDefault, in: theme))
                    .accessibilityLabel(Text(verbatim: detail.lines.joined(separator: " · ")))
                if detail.lines.count > 1 {
                    InkTag(Text(copy: "+\(detail.lines.count - 1) 项", bundle: .module))
                        .padding(.leading, Space.xs)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("squadcard.dayLine.more")
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let meals = detail.meals {
                Count(label: Text(copy: "健康餐", bundle: .module), value: meals.healthy)
                Count(label: Text(copy: "放纵餐", bundle: .module), value: meals.cheat)
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
