#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// 下午8:03–8:23 with a clock, in the place row's look: when a 训练 was done, apart from when it
/// was posted. A Health workout's moments are on the viewer's clock; a start picked by hand is the
/// author's own hour and minute, drawn on GMT so no zone moves it.
struct WorkoutTimeTag: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    let time: WorkoutTime

    var body: some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: "clock")
                .font(.system(size: Sizing.smallIcon - 3, weight: .semibold))
                .accessibilityHidden(true)
            Text(verbatim: words)
                .typeStyle(TypeRamp.footnote)
                .lineLimit(1)
        }
        .foregroundStyle(Color(role: .fgMuted, in: theme))
        .frame(minHeight: Sizing.smallTag)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("post.workoutTime")
    }

    private var words: String {
        switch time {
        case .moments(let start, let end):
            return Self.span(start.date, end.date, in: timeZone, locale: locale)
        case .wallClock(let start, let minutes):
            guard let begun = Self.gmt.date(from: DateComponents(year: 2001, hour: start.hour, minute: start.minute))
            else { return "" }
            guard let minutes else {
                return begun.formatted(Date.FormatStyle(locale: locale, timeZone: .gmt).hour().minute())
            }
            return Self.span(begun, begun.addingTimeInterval(TimeInterval(minutes * 60)), in: .gmt, locale: locale)
        }
    }

    /// 下午8:03–8:23, the system's way of saying a span of the same day once. One past midnight is
    /// the two times alone (晚上11:50–上午12:10), since the system would add both dates.
    private static func span(_ start: Date, _ end: Date, in zone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard calendar.isDate(start, inSameDayAs: end) else {
            let clock = Date.FormatStyle(locale: locale, timeZone: zone).hour().minute()
            return "\(start.formatted(clock))–\(end.formatted(clock))"
        }
        return (start..<max(start, end)).formatted(
            Date.IntervalFormatStyle(locale: locale, timeZone: zone).hour().minute())
    }

    private static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
#endif
