#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A small label over a group of choices, such as 最近使用 or 全部运动.
public struct SectionLabel: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text

    public init(_ title: Text) {
        self.title = title
    }

    public var body: some View {
        title
            .typeStyle(TypeRamp.sectionLabel)
            .foregroundStyle(Color(role: .textSecondary, in: theme))
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
