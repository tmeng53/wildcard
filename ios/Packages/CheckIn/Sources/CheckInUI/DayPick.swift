#if os(iOS)
import Contracts
import DesignSystemUI
import SwiftUI

/// 日期 on a new post's page (补打卡): today and the week before it in one line, today picked
/// first, in the brand graphite. A day in `blocked` can't be picked.
struct DayPick: View {
    let days: [LocalDay]
    var blocked: Set<LocalDay> = []
    @Binding var picked: LocalDay

    var body: some View {
        DayStrip(strip, picked: $picked)
            .accentTone(.brand)
    }

    private var strip: [DayStrip<LocalDay>.Day] {
        days.map { day in
            DayStrip<LocalDay>.Day(
                id: day, date: day.day, weekday: day.weekday, isToday: day == days.last,
                isEnabled: !blocked.contains(day))
        }
    }
}

extension LocalDay {
    /// Noon of this day on the phone's calendar, to format it as a date.
    var date: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }
}
#endif
