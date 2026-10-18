#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A Liquid Glass search capsule: a magnifier, the text, and a clear button once there is text.
/// Glass because it floats over the content it searches; a signature ring while it has focus.
public struct SearchField: View {
    @Environment(\.sceneTheme) private var theme
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
                .font(.system(size: Sizing.pillGlyph, weight: .medium))
                .foregroundStyle(Color(role: .textSecondary, in: theme))
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.foregroundStyle(Color(role: .textTertiary, in: theme))) {
                prompt
            }
            .typeStyle(TypeRamp.field)
            .foregroundStyle(Color(role: .textPrimary, in: theme))
            .tint(Color(role: .signature, in: theme))
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Sizing.pillGlyph))
                        .foregroundStyle(Color(role: .textTertiary, in: theme))
                        .frame(width: Space.xl, height: Sizing.searchFieldHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("清除", bundle: .module))
            }
        }
        .padding(.leading, Space.s + Space.xxs / 2)
        .padding(.trailing, Space.xxs)
        .frame(height: Sizing.searchFieldHeight)
        .glassEffect(.regular, in: Capsule())
        .overlay {
            if isFocused {
                Capsule().strokeBorder(Color(role: .signature, in: theme), lineWidth: Sizing.selectionStroke)
            }
        }
    }
}
#endif
