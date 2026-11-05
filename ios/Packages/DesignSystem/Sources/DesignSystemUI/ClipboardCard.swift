#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A sheet on a clipboard (the approved 战术板): white, an ink outline and an ink clip over its top
/// edge, for the coach's line of the day wherever it is pinned (动态's top, the coach's 简历). The
/// content brings its own padding.
public struct ClipboardCard<Content: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private static var clip: CGSize { CGSize(width: 54, height: 12) }
    private static var border: Double { 1.5 }

    public var body: some View {
        content
            .background(
                Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: Self.border)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color(role: .fgDefault, in: theme))
                    .frame(width: Self.clip.width, height: Self.clip.height)
                    .offset(y: -Self.clip.height / 2)
                    .accessibilityHidden(true)
            }
            .padding(.top, Self.clip.height / 2)
    }
}
#endif
