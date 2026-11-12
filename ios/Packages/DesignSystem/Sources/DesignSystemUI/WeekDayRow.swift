#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// My week in one line, Monday to Sunday: each day's small circle over its name, spread across
/// the width it is given. The folded squad card draws it `.compact`, today named 今天; the small
/// home screen widget `.tiny`, today's weekday in ink; the medium 本周出赛表 widget `.regular`,
/// with each day's sport named under it.
public struct WeekDayRow: View {
    public enum Size: Sendable {
        case regular
        case compact
        case tiny
    }

    @Environment(\.sceneTheme) private var theme

    private let days: [WeekDayStatus]
    private let today: Int?
    private let size: Size
    private let captions: [Text]?

    /// - Parameters:
    ///   - days: Monday first, seven days.
    ///   - today: today's index in `days`, or nil when today isn't in this week.
    ///   - captions: a line under each day, Monday first, such as its sport.
    public init(days: [WeekDayStatus], today: Int?, size: Size = .compact, captions: [Text]? = nil) {
        self.days = days
        self.today = today
        self.size = size
        self.captions = captions
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, status in
                VStack(spacing: Space.xxs) {
                    DayCircle(status: status, isToday: index == today, isPicked: false, weekday: index, size: circle)
                        .fixedSize()
                    if let captions, captions.indices.contains(index) {
                        captions[index]
                            .typeStyle(index == today ? TypeRamp.tabSelected : TypeRamp.tab)
                            .foregroundStyle(Color(role: index == today ? .fgDefault : .fgMuted, in: theme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                if index < days.count - 1 { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var circle: DayCircle.Size {
        switch size {
        case .regular: .regular
        case .compact: .compact
        case .tiny: .tiny
        }
    }
}
#endif
