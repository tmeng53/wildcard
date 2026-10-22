#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The small letter-spaced label over a group or a number (最常见, 本周小队训练).
public struct SectionLabel: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text

    public init(_ title: Text) {
        self.title = title
    }

    public var body: some View {
        title
            .typeStyle(TypeRamp.label)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
