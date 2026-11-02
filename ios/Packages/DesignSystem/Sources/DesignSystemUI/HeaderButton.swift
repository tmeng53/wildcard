#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A 44-point round button in a header (返回, 设置, 撤销, 关闭) in the system's interactive Liquid
/// Glass, as iOS draws a navigation bar's buttons, on every surface: an ink glyph on a white page
/// or over the scene, a white one over photos on ink (关闭 in the photo viewer). An icon only, so
/// `label` names it for VoiceOver.
public struct HeaderButton: View {
    public enum Surface: Sendable {
        /// On a white page.
        case page
        /// Over the scene or the character's stage.
        case scene
        /// Over photos on ink, full screen.
        case ink
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let label: Text
    private let systemImage: String
    private let surface: Surface
    private let action: () -> Void
    /// The symbol's point size: it fills the same box as the design's 20-point line icons.
    private let glyph: Double = 17

    public init(_ label: Text, systemImage: String, on surface: Surface = .page, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.surface = surface
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Color(role: glyphRole, in: theme))
                .frame(width: Sizing.control, height: Sizing.control)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(label)
    }

    private var glyphRole: ColorRole {
        switch (surface, isEnabled) {
        case (.ink, true): .fgOnInk
        case (.ink, false): .fgOnInkMuted
        case (_, true): .fgDefault
        case (_, false): .fgSubtle
        }
    }
}

/// The header of a task step in sign-up: a back button, then the step segments, centered.
public struct StepHeader: View {
    private let step: Int?
    private let count: Int
    private let onBack: () -> Void

    /// A nil `step` is a step the task doesn't count: back alone, no segments.
    public init(step: Int?, of count: Int, onBack: @escaping () -> Void) {
        self.step = step
        self.count = count
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: Space.l) {
            HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: onBack)
            if let step {
                StepSegments(step: step, of: count)
            } else {
                Spacer(minLength: 0)
            }
            // Keeps the segments centered: as wide as the back button.
            Color.clear.frame(width: Sizing.control, height: Sizing.control)
        }
        .frame(height: Sizing.control)
    }
}

/// Where a task is: one ink segment per step done or current, a grey one per step to go.
/// VoiceOver reads it as 「第 2 步，共 4 步」.
public struct StepSegments: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let step: Int
    private let count: Int

    /// `step` counts from 1 and is clamped to `1...count`.
    public init(step: Int, of count: Int) {
        self.count = max(count, 1)
        self.step = min(max(step, 1), self.count)
    }

    public var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(1...count, id: \.self) { index in
                Capsule()
                    .fill(Color(role: index <= step ? .fgDefault : .borderDefault, in: theme))
                    .frame(height: Sizing.progress)
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("第 \(step) 步，共 \(count) 步", bundle: .module))
    }
}
#endif
