#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A short run of days in one line, one to pick (补打卡's 日期: today and the week before it).
/// Each day is the squad card's day circle with its date in it and its weekday over it; today is
/// called 今天 and ringed in ink, the picked day fills with the accent tone, and a day that can't
/// be picked sits in grey. The days share the width; nothing scrolls.
public struct DayStrip<ID: Hashable & Sendable>: View {
    /// One day of the strip.
    public struct Day: Identifiable, Sendable {
        public let id: ID
        /// The day of the month, in the circle.
        public let date: Int
        /// Monday is 1, Sunday 7.
        public let weekday: Int
        public let isToday: Bool
        /// False greys it out and it can't be picked.
        public let isEnabled: Bool

        public init(id: ID, date: Int, weekday: Int, isToday: Bool, isEnabled: Bool = true) {
            self.id = id
            self.date = date
            self.weekday = weekday
            self.isToday = isToday
            self.isEnabled = isEnabled
        }
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let days: [Day]
    @Binding private var picked: ID

    public init(_ days: [Day], picked: Binding<ID>) {
        self.days = days
        _picked = picked
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Button {
                    guard day.id != picked else { return }
                    taps += 1
                    picked = day.id
                } label: {
                    cell(day, isPicked: day.id == picked)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!day.isEnabled)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(day))
                // Ignoring the children drops the button trait, so it is added back.
                .accessibilityAddTraits(day.id == picked ? [.isButton, .isSelected] : .isButton)
                // dayStrip.0 is the earliest day.
                .accessibilityIdentifier("dayStrip.\(index)")
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: picked)
        .haptic(.pick, trigger: taps)
    }

    private func cell(_ day: Day, isPicked: Bool) -> some View {
        VStack(spacing: Space.xxs) {
            Group {
                if day.isToday { Text(copy: "今天", bundle: .module) } else { WeekdayName.short(day.weekday - 1) }
            }
            .typeStyle(day.isToday ? TypeRamp.tabSelected : TypeRamp.tab)
            .foregroundStyle(Color(role: !day.isEnabled ? .fgSubtle : day.isToday ? .fgDefault : .fgMuted, in: theme))
            .lineLimit(1)
            .fixedSize()
            Text(verbatim: "\(day.date)")
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: numberColor(day, isPicked: isPicked), in: theme))
                .frame(width: SquadCardMetrics.day, height: SquadCardMetrics.day)
                .background { circle(day, isPicked: isPicked) }
        }
        // Answers taps across its share of the width and the full height, not just the circle;
        // eight days fit a 320-point phone, so no minimum width.
        .frame(maxWidth: .infinity, minHeight: Sizing.minimumTapTarget)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func circle(_ day: Day, isPicked: Bool) -> some View {
        if isPicked {
            Circle().fill(Color(role: tone.fill, in: theme))
        } else if !day.isEnabled {
            Circle().fill(Color(role: .bgSubtle, in: theme))
        } else {
            Circle()
                .fill(Color(role: .bgCanvas, in: theme))
                .overlay(
                    Circle().strokeBorder(
                        Color(role: day.isToday ? .fgDefault : .borderDefault, in: theme),
                        lineWidth: day.isToday ? SquadCardMetrics.todayStroke : Sizing.selectionStroke))
        }
    }

    private func numberColor(_ day: Day, isPicked: Bool) -> ColorRole {
        if isPicked { return tone.onFill }
        return day.isEnabled ? .fgDefault : .fgSubtle
    }

    /// 今天 or 周日, then the date: VoiceOver reads which day it is.
    private func label(_ day: Day) -> Text {
        let name = day.isToday ? Text(copy: "今天", bundle: .module) : WeekdayName.full(day.weekday - 1)
        return name + Text(verbatim: " \(day.date)")
    }
}
#endif
