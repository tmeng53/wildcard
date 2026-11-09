#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The start of a 训练 made by hand, at the front of the 开始 · 时长 row: 「--:--」 until one is
/// picked, whose tap opens the flip clock on the phone's time; once picked, the time with a
/// cross, whose tap clears it, as a second tap clears a length.
struct StartTimePill: View {
    @Binding var startTime: StartTime?
    @State private var isPicking = false

    var body: some View {
        PickPill(
            Text(verbatim: startTime?.wire ?? "--:--"), systemImage: "clock", look: .solid,
            isSelected: startTime != nil, isRemovable: startTime != nil
        ) {
            if startTime == nil { isPicking = true } else { startTime = nil }
        }
        .monospacedDigit()
        .accessibilityLabel(Text("开始时间", bundle: .module))
        .accessibilityValue(Text(verbatim: startTime?.wire ?? ""))
        .accessibilityIdentifier("compose.start")
        .sheet(isPresented: $isPicking) {
            FlipClockSheet(start: Self.now) { picked in
                startTime = picked
                isPicking = false
            } cancel: {
                isPicking = false
            }
            .presentationDetents([.height(FlipClockSheet.height)])
            .presentationDragIndicator(.visible)
        }
    }

    /// The phone's time, to the minute: where the clock opens.
    private static var now: StartTime? {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return try? StartTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

/// 开始时间: a short sheet with the hour and the minute on `DesignSystemUI`'s flip clock.
struct FlipClockSheet: View {
    @Environment(\.sceneTheme) private var theme
    @State private var values: [Int]
    let done: (StartTime) -> Void
    let cancel: () -> Void

    init(start: StartTime?, done: @escaping (StartTime) -> Void, cancel: @escaping () -> Void) {
        _values = State(initialValue: [start?.hour ?? 0, start?.minute ?? 0])
        self.done = done
        self.cancel = cancel
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            ComposeBar(
                title: Text("开始时间", bundle: .module), finish: Text("完成", bundle: .module), isWorking: false,
                canFinish: true, cancelID: "start.cancel", finishID: "start.done", cancel: cancel
            ) {
                guard let picked = try? StartTime(hour: values[0], minute: values[1]) else { return }
                done(picked)
            }
            FlipClockView(
                .timeOfDay, values: $values,
                labels: [Text("小时", bundle: .module), Text("分钟", bundle: .module)],
                identifiers: ["start.hour", "start.minute"], size: .large, separator: .colon
            )
            .padding(.bottom, Space.m)
        }
        .padding(.top, Space.s)
        .frame(maxWidth: .infinity)
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
    }

    /// The sheet's height: the bar, the two cards with their chevrons, and a margin.
    static let height: Double = 300
}
#endif
