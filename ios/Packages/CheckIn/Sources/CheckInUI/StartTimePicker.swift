#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The start of a 训练 made by hand, at the front of the 开始 · 时长 row: the time, whose tap opens
/// the flip clock on it to pick another. Never cleared (Tracy, 2026-11-11: every 训练 has a start);
/// only an edit of an older post shows 「--:--」 until one is picked, on the phone's time.
struct StartTimePill: View {
    @Binding var startTime: StartTime?
    @State private var isPicking = false

    var body: some View {
        PickPill(
            Text(verbatim: startTime?.wire ?? "--:--"), systemImage: "clock", look: .solid,
            isSelected: startTime != nil, isRemovable: false
        ) {
            isPicking = true
        }
        .monospacedDigit()
        .accessibilityLabel(Text(copy: "开始时间", bundle: .module))
        .accessibilityValue(Text(verbatim: startTime?.wire ?? ""))
        .accessibilityIdentifier("compose.start")
        .sheet(isPresented: $isPicking) {
            FlipClockSheet(start: startTime ?? .phoneNow) { picked in
                startTime = picked
                isPicking = false
            } cancel: {
                isPicking = false
            }
            .presentationDetents([.height(FlipClockSheet.height)])
            .presentationDragIndicator(.visible)
        }
    }
}

extension StartTime {
    /// The phone's time, to the minute, on its own clock: a new 训练's start.
    static var phoneNow: StartTime? {
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
                title: Text(copy: "开始时间", bundle: .module), finish: Text(copy: "完成", bundle: .module), isWorking: false,
                canFinish: true, cancelID: "start.cancel", finishID: "start.done", cancel: cancel
            ) {
                guard let picked = try? StartTime(hour: values[0], minute: values[1]) else { return }
                done(picked)
            }
            FlipClockView(
                .timeOfDay, values: $values,
                labels: [Text(copy: "小时", bundle: .module), Text(copy: "分钟", bundle: .module)],
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
