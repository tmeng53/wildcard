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

/// A word in a header (取消, 保存, 发布), in the same interactive Liquid Glass as `HeaderButton`:
/// a 44-point capsule as tall as the round buttons beside it. `prominent` is the header's one
/// action that finishes the page (发布, 保存): glass tinted in the accent tone's colour with its
/// words in the tone's ink, as iOS draws a toolbar's prominent button. Disabled, a prominent one
/// turns clear with quiet words. `isWorking` swaps the words for the loading dots while its call
/// is under way, keeping the button's width.
public struct HeaderTextButton: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Environment(\.isEnabled) private var isEnabled
    private let title: Text
    private let prominent: Bool
    private let isWorking: Bool
    private let surface: HeaderButton.Surface
    private let action: () -> Void

    public init(
        _ title: Text, prominent: Bool = false, isWorking: Bool = false, on surface: HeaderButton.Surface = .page,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.prominent = prominent
        self.isWorking = isWorking
        self.surface = surface
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            title
                .typeStyle(TypeRamp.calloutEmphasis)
                .lineLimit(1)
                .loadingLabel(isWorking)
                .foregroundStyle(Color(role: wordsRole, in: theme))
                .padding(.horizontal, Space.m)
                .frame(minWidth: Sizing.control, minHeight: Sizing.control)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(glass, in: Capsule())
    }

    // Stays tinted while its call runs, so it doesn't flash clear under the dots.
    private var tinted: Bool { prominent && (isEnabled || isWorking) }

    private var glass: Glass {
        tinted ? .regular.tint(Color(role: tone.fill, in: theme)).interactive() : .regular.interactive()
    }

    private var wordsRole: ColorRole {
        switch (surface, isEnabled) {
        case _ where tinted: tone.onFill
        case (.ink, true): .fgOnInk
        case (.ink, false): .fgOnInkMuted
        case (_, true): .fgDefault
        case (_, false): .fgSubtle
        }
    }
}

/// `HeaderButton`'s look for a button that opens a glass menu (the 「…」 on the member's own
/// post): the same 44-point Liquid Glass circle and glyph, the menu growing out of it. `.ink` is
/// for a button over any photo or post face, light or dark: a white glyph on glass darkened as
/// the photo tiles' × is, so it reads on both.
public struct HeaderMenu: View {
    @Environment(\.sceneTheme) private var theme
    private let label: Text
    private let systemImage: String
    private let surface: HeaderButton.Surface
    private let items: [GlassMenuItem]
    @State private var isOpen = false
    private let glyph: Double = 17
    /// How dark the glass is on a dark or photo face.
    private let inkTint: Double = 0.5

    public init(
        _ label: Text, systemImage: String = "ellipsis", on surface: HeaderButton.Surface = .page,
        items: [GlassMenuItem]
    ) {
        self.label = label
        self.systemImage = systemImage
        self.surface = surface
        self.items = items
    }

    public var body: some View {
        Button {
            isOpen = true
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Color(role: surface == .ink ? .fgOnInk : .fgDefault, in: theme))
                .frame(width: Sizing.control, height: Sizing.control)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: Circle())
        .accessibilityLabel(label)
        .glassMenu(isPresented: $isOpen, items: items)
    }

    private var glass: Glass {
        surface == .ink
            ? .regular.tint(Color(role: .bgInk, in: theme).opacity(inkTint)).interactive()
            : .regular.interactive()
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
