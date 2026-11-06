#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SportsUI
import SwiftUI

/// 训练记录 on 我: how many days the member trained, over a heatmap of their last weeks (a column
/// a week, Monday on top, four shades of ink by how long each day was) with the months under it.
/// A tap on a day rings it and opens the system's popover over it, its arrow on the day: the
/// day, its sport and minutes, which opens its post; a day without a 练了 says so.
struct TrainingRecordView: View {
    let record: TrainingRecord
    let trainedDays: Int
    let openPost: (CheckInID) -> Void
    @State private var selected: LocalDay?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("训练记录", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text("\(trainedDays) 天", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(Array(record.columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: Self.gap) {
                        ForEach(week) { day in
                            // The selected day's ring reaches past the gap: drawn over its neighbours.
                            cell(day).zIndex(selected == day.day ? 1 : 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .zIndex(week.contains { $0.day == selected } ? 1 : 0)
                }
            }
            months
        }
        .accessibilityIdentifier("me.record")
    }

    private func cell(_ day: TrainingRecord.Day) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        let isSelected = selected == day.day
        return Button {
            selected = day.day
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background {
                    if day.isAhead {
                        shape.strokeBorder(
                            Color(role: .borderDefault, in: theme),
                            style: StrokeStyle(lineWidth: Sizing.hairline, dash: [2, 2]))
                    } else {
                        shape.fill(Color(role: shade(day.level), in: theme))
                    }
                }
                .overlay {
                    if isSelected {
                        shape
                            .strokeBorder(Color(role: .bgCanvas, in: theme), lineWidth: Self.ring)
                            .padding(-Self.ring)
                            .overlay(
                                shape.strokeBorder(Color(role: .bgBrand, in: theme), lineWidth: Self.ring)
                                    .padding(-Self.ring * 2))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isAhead)
        .accessibilityLabel(Text(Self.date(day.day), format: Self.dateStyle.locale(locale)))
        .accessibilityValue(summary(day))
        .accessibilityIdentifier("me.record.cell")
        .popover(
            isPresented: Binding(
                get: { isSelected },
                set: { if !$0, selected == day.day { selected = nil } }),
            arrowEdge: .top
        ) {
            DayPopover(day: day) { post in
                selected = nil
                openPost(post)
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    /// The month names under the columns where a month begins.
    private var months: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(Array(record.columns.enumerated()), id: \.offset) { index, week in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: 0)
                    .overlay(alignment: .topLeading) {
                        if let month = record.months.first(where: { $0.column == index })?.month,
                            let first = week.first(where: { $0.day.month == month && $0.day.day == 1 })
                        {
                            Text(Self.date(first.day), format: Self.monthStyle.locale(locale))
                                .typeStyle(TypeRamp.caption)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .fixedSize()
                        }
                    }
            }
        }
        .frame(height: Self.monthRow, alignment: .top)
        .accessibilityHidden(true)
    }

    private func summary(_ day: TrainingRecord.Day) -> Text {
        guard let main = day.main else { return Text("没训练", bundle: .module) }
        if let minutes = day.minutes {
            return main.activity.name + Text(verbatim: " ") + Text("\(minutes) 分钟", bundle: .module)
        }
        return main.activity.name
    }

    private func shade(_ level: TrainingRecord.Level) -> ColorRole {
        switch level {
        case .none: .bgSubtle
        case .light: .fgSubtle
        case .steady: .fgMuted
        case .hard: .bgBrand
        }
    }

    /// The day at noon UTC, for the date formats (which read it in UTC).
    static func date(_ day: LocalDay) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? .now
    }

    /// 10月22日 / Oct 22.
    static var dateStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = .gmt
        return style
    }

    /// 10月 / Oct.
    static var monthStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.abbreviated)
        style.timeZone = .gmt
        return style
    }

    /// Between days and weeks.
    private static var gap: Double { 3 }
    private static var corner: Double { 3 }
    /// The selected day's ring, white then graphite.
    private static var ring: Double { 2 }
    private static var monthRow: Double { 14 }
}

/// What a tapped day's popover says: 10月22日 · 跑步 45′ ›, opening its post, or 10月22日 · 没训练.
private struct DayPopover: View {
    let day: TrainingRecord.Day
    let open: (CheckInID) -> Void
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        if let post = day.post, let main = day.main {
            Button {
                open(post)
            } label: {
                HStack(spacing: Space.xs) {
                    line(main.activity.name)
                    if let minutes = day.minutes {
                        Text(verbatim: "\(minutes)′")
                            .typeStyle(TypeRamp.scoreSmall)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: Sizing.smallIcon * 0.8, weight: .semibold))
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Space.m)
                .frame(minHeight: Sizing.control)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .accessibilityIdentifier("me.record.day")
        } else {
            line(Text("没训练", bundle: .module))
                .padding(.horizontal, Space.m)
                .frame(minHeight: Sizing.control)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .accessibilityIdentifier("me.record.day")
        }
    }

    private func line(_ what: Text) -> some View {
        HStack(spacing: Space.xs) {
            Text(TrainingRecordView.date(day.day), format: TrainingRecordView.dateStyle.locale(locale))
            Text(verbatim: "·").foregroundStyle(Color(role: .fgMuted, in: theme))
            what
        }
        .typeStyle(TypeRamp.calloutEmphasis)
        .lineLimit(1)
        .fixedSize()
    }
}
#endif
