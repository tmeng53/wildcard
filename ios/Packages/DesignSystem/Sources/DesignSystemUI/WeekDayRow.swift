#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// My week in one line, Monday to Sunday: each day's small circle over its name, spread across
/// the width it is given. The folded squad card draws it `.compact`, today named 今天; the small
/// home screen widget `.tiny`, today's weekday in ink.
public struct WeekDayRow: View {
    public enum Size: Sendable {
        case compact
        case tiny
    }

    private let days: [WeekDayStatus]
    private let today: Int?
    private let size: Size

    /// - Parameters:
    ///   - days: Monday first, seven days.
    ///   - today: today's index in `days`, or nil when today isn't in this week.
    public init(days: [WeekDayStatus], today: Int?, size: Size = .compact) {
        self.days = days
        self.today = today
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, status in
                DayCircle(
                    status: status, isToday: index == today, isPicked: false, weekday: index,
                    size: size == .compact ? .compact : .tiny
                )
                .fixedSize()
                if index < days.count - 1 { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
