#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A number picked by sliding a ruler (刻度) under a fixed needle, like a kitchen scale: the big
/// number above, the marks from `scale` below, long ones labelled. It always holds a value; it
/// stops only on the scale's values and ticks once for each mark that passes the needle. The
/// needle wears the accent tone, the marks stay neutral. For a number where the exact value
/// matters less than getting near it fast (发动态's minutes under 其他).
public struct TickRuler: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Binding private var value: Int
    private let scale: RulerScale
    private let label: Text
    private let unit: Text
    @State private var position = ScrollPosition(edge: .leading)
    @State private var width: Double = 0
    @State private var isDragging = false

    /// The gap from one mark to the next.
    private let pitch: Double = 12
    private let markWidth: Double = 2
    private let rulerHeight: Double = 56
    private let needleWidth: Double = 3
    private let needleHeight: Double = 30
    /// From the top of the ruler to the labels under the long marks.
    private let labelTop: Double = 30

    /// `label` names the ruler for VoiceOver with its unit (时长 · 分钟); `unit` follows the number on
    /// screen (分钟).
    public init(value: Binding<Int>, scale: RulerScale, label: Text, unit: Text) {
        _value = value
        self.scale = scale
        self.label = label
        self.unit = unit
    }

    public var body: some View {
        VStack(spacing: Space.xxs) {
            readout
            ruler
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: "\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = scale.value(value, movedBy: 1)
            case .decrement: value = scale.value(value, movedBy: -1)
            @unknown default: break
            }
        }
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            Text(verbatim: "\(value)")
                .typeStyle(TypeRamp.scoreCard)
                .monospacedDigit()
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            unit
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
    }

    private var ruler: some View {
        // The ends pad the marks so the first and last can reach the needle in the middle.
        let end = max((width - pitch) / 2, 0)
        return ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Color.clear.frame(width: end)
                ForEach(scale.values, id: \.self) { mark in
                    markView(mark)
                }
                Color.clear.frame(width: end)
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .scrollTargetBehavior(MarkSnapping(pitch: pitch))
        .frame(height: rulerHeight)
        .onScrollPhaseChange { _, phase in
            isDragging = phase == .interacting || phase == .decelerating
        }
        .onScrollGeometryChange(for: Int.self) { geometry in
            Int((Double(geometry.contentOffset.x) / pitch).rounded())
        } action: { _, index in
            // Only the member's own sliding picks; moving the ruler to `value` doesn't.
            guard isDragging else { return }
            let picked = scale.value(atIndex: index)
            if picked != value { value = picked }
        }
        .onGeometryChange(for: Double.self) {
            Double($0.size.width)
        } action: { newWidth in
            width = newWidth
            scrollToValue()
        }
        .onChange(of: value) { _, _ in
            if !isDragging { scrollToValue() }
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color(role: tone.fill, in: theme))
                .frame(width: needleWidth, height: needleHeight)
                .allowsHitTesting(false)
        }
        .horizontalScrollFade()
        .haptic(.pick, trigger: value) { _, _ in isDragging }
    }

    private func markView(_ mark: Int) -> some View {
        let kind = scale.mark(for: mark)
        return ZStack(alignment: .top) {
            Capsule()
                .fill(Color(role: kind == .major ? .fgDefault : .fgSubtle, in: theme))
                .frame(width: markWidth, height: markHeight(kind))
            if kind == .major {
                Text(verbatim: "\(mark)")
                    .typeStyle(TypeRamp.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .fixedSize()
                    .padding(.top, labelTop)
            }
        }
        .frame(width: pitch, height: rulerHeight, alignment: .top)
    }

    private func markHeight(_ kind: RulerScale.Mark) -> Double {
        switch kind {
        case .minor: 12
        case .mid: 18
        case .major: 24
        }
    }

    private func scrollToValue() {
        position.scrollTo(x: Double(scale.index(of: value)) * pitch)
    }
}

/// Lets a flick come to rest only with a mark under the needle.
private struct MarkSnapping: ScrollTargetBehavior {
    let pitch: Double

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let furthest = max(Double(context.contentSize.width - context.containerSize.width), 0)
        let snapped = (Double(target.rect.origin.x) / pitch).rounded() * pitch
        target.rect.origin.x = CGFloat(min(max(snapped, 0), furthest))
    }
}
#endif
