#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A one-line text field: white with a hairline, 44 tall, an accent border while typing, and a
/// count like `3/10` when it has a limit. The field doesn't cut the text; the caller enforces
/// `limit` where it saves. `onFocusChange` tells the screen when typing starts and stops, so it
/// can keep the field above the keyboard.
public struct InputField: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Binding private var text: String
    @FocusState private var isFocused: Bool
    private let label: Text
    private let prompt: Text?
    private let limit: Int?
    private let onFocusChange: (Bool) -> Void

    /// `label` names the field for VoiceOver; `prompt` is the placeholder.
    public init(
        text: Binding<String>, label: Text, prompt: Text? = nil, limit: Int? = nil,
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _text = text
        self.label = label
        self.prompt = prompt
        self.limit = limit
        self.onFocusChange = onFocusChange
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        HStack(spacing: Space.xs) {
            TextField(text: $text, prompt: prompt?.foregroundStyle(Color(role: .fgSubtle, in: theme))) {
                label
            }
            .typeStyle(TypeRamp.field)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .tint(Color(role: tone.fill, in: theme))
            .focused($isFocused)
            if let limit {
                Text(verbatim: "\(text.count)/\(limit)")
                    .typeStyle(TypeRamp.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.s + 2)
        .frame(minHeight: Sizing.control)
        .background(Color(role: .bgCanvas, in: theme), in: shape)
        .overlay { PickBorder(shape: shape, isSelected: isFocused) }
        .contentShape(shape)
        .onTapGesture { isFocused = true }
        .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
        .animation(.wildcard(Motion.change), value: isFocused)
    }
}

/// A search field: a subtle grey block with a magnifier, the text, and a clear button once there
/// is text.
public struct SearchField: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Binding private var text: String
    @FocusState private var isFocused: Bool
    private let prompt: Text

    public init(text: Binding<String>, prompt: Text) {
        _text = text
        self.prompt = prompt
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.foregroundStyle(Color(role: .fgMuted, in: theme))) {
                prompt
            }
            .typeStyle(TypeRamp.field)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .tint(Color(role: tone.fill, in: theme))
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Sizing.smallIcon))
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                        .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("清除", bundle: .module))
            }
        }
        .padding(.leading, Space.s)
        .frame(minHeight: Sizing.control)
        .background(
            Color(role: .bgSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        )
        // A tap anywhere on the field, not only on the text, starts typing.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}
#endif
