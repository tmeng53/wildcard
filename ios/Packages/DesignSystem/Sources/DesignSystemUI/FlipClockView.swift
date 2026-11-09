#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A flip clock: a row of graphite flip cards, one per `FlipClock` column, each with a chevron
/// above (next page) and below (the one before). A drag up or down turns a page every 24 points,
/// and a fling keeps turning them one by one. The rules (ranges, wrapping, a day held to its
/// month) are the clock's; the view only draws them. 开始时间 is two cards, a birthday three.
public struct FlipClockView: View {
    /// How big the cards are: `large` for a sheet of its own (开始时间), `regular` for a clock on a
    /// page with other things on it (生日).
    public enum Size: Hashable, Sendable {
        case large
        case regular

        var digits: TypeStyle { self == .large ? TypeRamp.scoreEnding : TypeRamp.scoreHero }
        var height: Double { self == .large ? 132 : 92 }
        /// Wide enough for the figures in the scoreboard face plus a margin each side.
        func width(digits: Int) -> Double {
            let figure: Double = self == .large ? 44 : 30
            let margin: Double = self == .large ? 36 : 24
            return Double(digits) * figure + margin
        }
    }

    /// What stands between the cards: a clock's colon, or nothing.
    public enum Separator: Hashable, Sendable {
        case colon
        case none
    }

    @Environment(\.sceneTheme) private var theme
    private let clock: FlipClock
    @Binding private var values: [Int]
    private let labels: [Text]
    private let identifiers: [String]
    private let size: Size
    private let separator: Separator

    /// - Parameters:
    ///   - labels: each column's VoiceOver name (小时, 分钟; 年, 月, 日).
    ///   - identifiers: each column's accessibility identifier, for UI tests.
    public init(
        _ clock: FlipClock, values: Binding<[Int]>, labels: [Text], identifiers: [String],
        size: Size = .regular, separator: Separator = .none
    ) {
        precondition(labels.count == clock.columns.count && identifiers.count == clock.columns.count)
        self.clock = clock
        _values = values
        self.labels = labels
        self.identifiers = identifiers
        self.size = size
        self.separator = separator
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            ForEach(clock.columns.indices, id: \.self) { column in
                if column > 0, separator == .colon { colon }
                FlipColumn(
                    label: clock.label(shown[column], column: column),
                    width: size.width(digits: clock.columns[column].digits), size: size,
                    name: labels[column]
                ) { pages in
                    values = clock.turning(shown, column: column, by: pages)
                }
                .accessibilityIdentifier(identifiers[column])
            }
        }
    }

    /// The values as the clock holds them, whatever the binding was given.
    private var shown: [Int] { clock.settled(values) }

    private var colon: some View {
        VStack(spacing: Space.l) {
            ForEach(0..<2, id: \.self) { _ in
                Circle()
                    .fill(Color(role: .bgBrand, in: theme))
                    .frame(width: Self.dot, height: Self.dot)
            }
        }
        .accessibilityHidden(true)
    }

    private static let dot: Double = 10
}

extension FlipClockView {
    /// 年 · 月 · 日 on regular cards: the year stops at `years`' ends, the month and day wrap, and
    /// the day runs to its month's length. Identifiers are `<prefix>.year`, `.month` and `.day`.
    public static func date(values: Binding<[Int]>, years: ClosedRange<Int>, identifier prefix: String) -> Self {
        FlipClockView(
            .date(years: years), values: values,
            labels: [Text("年", bundle: .module), Text("月", bundle: .module), Text("日期·日", bundle: .module)],
            identifiers: ["\(prefix).year", "\(prefix).month", "\(prefix).day"])
    }
}

/// One card with its chevrons. It asks to turn by a number of pages; the clock says where that
/// lands.
private struct FlipColumn: View {
    @Environment(\.sceneTheme) private var theme
    let label: String
    let width: Double
    let size: FlipClockView.Size
    let name: Text
    let turn: (Int) -> Void
    /// The pages the drag has turned so far, so each new one turns once.
    @State private var dragged = 0
    @State private var fling: Task<Void, Never>?

    var body: some View {
        VStack(spacing: Space.xxs) {
            chevron("chevron.up", by: 1)
            FlipCard(label: label, width: width, size: size)
                .contentShape(Rectangle())
                .gesture(drag)
            chevron("chevron.down", by: -1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(Text(verbatim: label))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turn(1)
            case .decrement: turn(-1)
            @unknown default: break
            }
        }
    }

    private func chevron(_ symbol: String, by step: Int) -> some View {
        Button {
            turn(step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .frame(width: width, height: Sizing.compactControl)
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
                let now = pages(gesture.translation.height)
                if now != dragged { turn(now - dragged) }
                dragged = now
            }
            .onEnded { gesture in
                let landed = pages(gesture.translation.height)
                if landed != dragged { turn(landed - dragged) }
                dragged = 0
                let extra = pages(gesture.predictedEndTranslation.height) - landed
                let turns = max(-Self.maxFling, min(Self.maxFling, extra))
                guard turns != 0 else { return }
                fling = Task { @MainActor in
                    for _ in 0..<abs(turns) {
                        try? await Task.sleep(for: .milliseconds(Self.flingPageMilliseconds))
                        guard !Task.isCancelled else { return }
                        turn(turns > 0 ? 1 : -1)
                    }
                }
            }
    }

    private func pages(_ height: Double) -> Int { Int((-height / Self.pageDrag).rounded(.towardZero)) }

    private static let pageDrag: Double = 24
    private static let maxFling = 30
    private static let flingPageMilliseconds = 45
}

/// A flip card: the figures in the scoreboard face on graphite, its top half a shade lighter, a
/// seam across the middle and a notch at each end. When the figures change, the old ones' top
/// half falls away over the new ones.
private struct FlipCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String
    let width: Double
    let size: FlipClockView.Size
    @State private var leaving: String?
    @State private var fall: Double = 0
    /// Counts the flips, so an earlier flip that ends during a later one leaves its page alone.
    @State private var flips = 0

    var body: some View {
        ZStack {
            face(label)
            if let leaving {
                face(leaving)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: size.height / 2)
                    }
                    .rotation3DEffect(
                        .degrees(-90 * fall), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
            }
            Rectangle()
                .fill(Color(role: .borderOnInk, in: theme))
                .frame(height: Self.seam)
        }
        .frame(width: width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.ticket))
        .overlay {
            HStack {
                notch
                Spacer()
                notch
            }
            .padding(.horizontal, -Self.notchWidth / 2)
        }
        .onChange(of: label) { old, _ in
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

    private func face(_ figures: String) -> some View {
        VStack(spacing: 0) {
            Color(role: .bgInk, in: theme)
            Color(role: .bgBrand, in: theme)
        }
        .overlay {
            Text(verbatim: figures)
                .typeStyle(size.digits)
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

    private static let seam: Double = 2
    private static let notchWidth: Double = 8
    private static let notchHeight: Double = 12
}
#endif
