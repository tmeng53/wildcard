#if os(iOS)
import Contracts
import DesignSystem
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

    /// The strip's height in a sheet: the weekday over the day's circle.
    static let height: Double = 64
}

/// The days a new post may count for, today last, and the one picked: nil is today. Only made
/// when there is a day to pick besides today.
struct DayChoice {
    let days: [LocalDay]
    let today: LocalDay
    let picked: Binding<LocalDay?>

    init?(days: [LocalDay], picked: Binding<LocalDay?>) {
        guard let today = days.last, days.count > 1 else { return nil }
        (self.days, self.today, self.picked) = (days, today, picked)
    }

    var shown: LocalDay { picked.wrappedValue ?? today }

    /// Picks `day`, keeping nil for today.
    func pick(_ day: LocalDay) {
        picked.wrappedValue = day == today ? nil : day
    }

    /// 「今天」, 「昨天」, or the date (「11/18」).
    func name(of day: LocalDay) -> Text {
        if day == today { return Text(copy: "今天", bundle: .module) }
        if day == days[days.count - 2] { return Text(copy: "昨天", bundle: .module) }
        let style = Date.FormatStyle.dateTime.month(.defaultDigits).day().locale(AppLanguage.current.locale)
        return Text(verbatim: day.date.formatted(style))
    }
}

/// 日期 folded into one pill (Tracy, 2026-11-21): the day picked, today to begin with, whose tap
/// opens the week's strip in a short sheet. A 训练 made by hand carries the day on its start pill
/// instead.
struct DayPill: View {
    let choice: DayChoice
    @State private var isPicking = false

    var body: some View {
        let name = choice.name(of: choice.shown)
        PickPill(name, systemImage: "calendar", look: .solid, isSelected: true, isRemovable: false) {
            isPicking = true
        }
        .accessibilityLabel(Text(copy: "日期", bundle: .module))
        .accessibilityValue(name)
        .accessibilityIdentifier("compose.day")
        .sheet(isPresented: $isPicking) {
            DaySheet(choice: choice) { isPicking = false }
                .presentationDetents([.height(DaySheet.height)])
                .presentationDragIndicator(.visible)
        }
    }
}

/// 日期: the week's strip under a bar with 取消 and 完成; nothing changes until 完成.
private struct DaySheet: View {
    let choice: DayChoice
    let close: () -> Void
    @Environment(\.sceneTheme) private var theme
    @State private var day: LocalDay

    init(choice: DayChoice, close: @escaping () -> Void) {
        self.choice = choice
        self.close = close
        _day = State(initialValue: choice.shown)
    }

    var body: some View {
        VStack(spacing: Space.m) {
            ComposeBar(
                title: Text(copy: "日期", bundle: .module), finish: Text(copy: "完成", bundle: .module), isWorking: false,
                canFinish: true, cancelID: "day.cancel", finishID: "day.done", cancel: close
            ) {
                choice.pick(day)
                close()
            }
            DayPick(days: choice.days, picked: $day)
                .padding(.horizontal, Space.pageMargin)
            Spacer(minLength: 0)
        }
        .padding(.top, Space.s)
        .frame(maxWidth: .infinity)
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
    }

    static let height: Double = 180
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
