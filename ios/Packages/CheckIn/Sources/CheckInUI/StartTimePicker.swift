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

/// 开始时间: a short sheet with the hour and the minute on graphite flip cards. Each turns a
/// page at a time on its chevrons, and with a drag up or down, a fling turning many.
struct FlipClockSheet: View {
    @Environment(\.sceneTheme) private var theme
    @State private var hour: Int
    @State private var minute: Int
    let done: (StartTime) -> Void
    let cancel: () -> Void

    init(start: StartTime?, done: @escaping (StartTime) -> Void, cancel: @escaping () -> Void) {
        _hour = State(initialValue: start?.hour ?? 0)
        _minute = State(initialValue: start?.minute ?? 0)
        self.done = done
        self.cancel = cancel
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            ComposeBar(
                title: Text("开始时间", bundle: .module), finish: Text("完成", bundle: .module), isWorking: false,
                canFinish: true, cancelID: "start.cancel", finishID: "start.done", cancel: cancel
            ) {
                guard let picked = try? StartTime(hour: hour, minute: minute) else { return }
                done(picked)
            }
            HStack(spacing: Space.s) {
                FlipColumn(value: $hour, count: 24, label: Text("小时", bundle: .module))
                    .accessibilityIdentifier("start.hour")
                VStack(spacing: Space.l) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(Color(role: .bgBrand, in: theme))
                            .frame(width: Self.dot, height: Self.dot)
                    }
                }
                .accessibilityHidden(true)
                FlipColumn(value: $minute, count: 60, label: Text("分钟", bundle: .module))
                    .accessibilityIdentifier("start.minute")
            }
            .padding(.bottom, Space.m)
        }
        .padding(.top, Space.s)
        .frame(maxWidth: .infinity)
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
    }

    /// The sheet's height: the bar, the two cards with their chevrons, and a margin.
    static let height: Double = 300
    private static let dot: Double = 10
}

/// One of the clock's cards with a chevron above and below: up turns to the next page, down
/// to the one before, wrapping round at `count`.
private struct FlipColumn: View {
    @Environment(\.sceneTheme) private var theme
    @Binding var value: Int
    let count: Int
    let label: Text
    @State private var dragStart: Int?
    @State private var fling: Task<Void, Never>?

    var body: some View {
        VStack(spacing: Space.xxs) {
            chevron("chevron.up", by: 1)
            FlipCard(value: value)
                .contentShape(Rectangle())
                .gesture(drag)
            chevron("chevron.down", by: -1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: FlipCard.twoDigits(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turn(by: 1)
            case .decrement: turn(by: -1)
            @unknown default: break
            }
        }
    }

    private func chevron(_ symbol: String, by step: Int) -> some View {
        Button {
            turn(by: step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .frame(width: FlipCard.width, height: Sizing.compactControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A drag up turns forward a page every `pageDrag` points, down turns back; let go fast and
    /// the pages keep turning, one by one, as far as the fling would have carried.
    private var drag: some Gesture {
        DragGesture(minimumDistance: Space.xxs)
            .onChanged { gesture in
                fling?.cancel()
                let start = dragStart ?? value
                dragStart = start
                set(start + pages(gesture.translation.height))
            }
            .onEnded { gesture in
                let start = dragStart ?? value
                dragStart = nil
                let landed = start + pages(gesture.translation.height)
                let extra = pages(gesture.predictedEndTranslation.height) - pages(gesture.translation.height)
                let turns = max(-Self.maxFling, min(Self.maxFling, extra))
                set(landed)
                guard turns != 0 else { return }
                fling = Task { @MainActor in
                    for _ in 0..<abs(turns) {
                        try? await Task.sleep(for: .milliseconds(Self.flingPageMilliseconds))
                        guard !Task.isCancelled else { return }
                        turn(by: turns > 0 ? 1 : -1)
                    }
                }
            }
    }

    private func pages(_ height: Double) -> Int { Int((-height / Self.pageDrag).rounded(.towardZero)) }

    private func turn(by step: Int) { set(value + step) }

    private func set(_ page: Int) { value = ((page % count) + count) % count }

    private static let pageDrag: Double = 24
    private static let maxFling = 30
    private static let flingPageMilliseconds = 45
}

/// A flip card: the number in the scoreboard face on graphite, its top half a shade lighter,
/// a seam across the middle and a notch at each end. When the number changes, the old one's
/// top half falls away over the new one.
private struct FlipCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    @State private var leaving: Int?
    @State private var fall: Double = 0
    /// Counts the flips, so an earlier flip that ends during a later one leaves its page alone.
    @State private var flips = 0

    var body: some View {
        ZStack {
            face(value)
            if let leaving {
                face(leaving)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: Self.height / 2)
                    }
                    .rotation3DEffect(
                        .degrees(-90 * fall), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
            }
            Rectangle()
                .fill(Color(role: .borderOnInk, in: theme))
                .frame(height: Self.seam)
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.ticket))
        .overlay {
            HStack {
                notch
                Spacer()
                notch
            }
            .padding(.horizontal, -Self.notchWidth / 2)
        }
        .onChange(of: value) { old, _ in
            guard !reduceMotion else { return }
            leaving = old
            fall = 0
            flips += 1
            let flip = flips
            withAnimation(.wildcard(Motion.press)) {
                fall = 1
            } completion: {
                if flip == flips { leaving = nil }
            }
        }
    }

    private func face(_ number: Int) -> some View {
        VStack(spacing: 0) {
            Color(role: .bgInk, in: theme)
            Color(role: .bgBrand, in: theme)
        }
        .overlay {
            Text(verbatim: Self.twoDigits(number))
                .typeStyle(TypeRamp.scoreEnding)
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var notch: some View {
        RoundedRectangle(cornerRadius: Radius.thumbnail / 2)
            .fill(Color(role: .bgCanvas, in: theme))
            .frame(width: Self.notchWidth, height: Self.notchHeight)
    }

    static func twoDigits(_ number: Int) -> String { number < 10 ? "0\(number)" : "\(number)" }

    static let width: Double = 124
    static let height: Double = 132
    private static let seam: Double = 2
    private static let notchWidth: Double = 8
    private static let notchHeight: Double = 12
}
#endif
