#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// 「教练」: the graphite tag beside the AI coach's name wherever it speaks (its 战术板 line, its
/// replies), so nobody takes its words for a teammate's.
public struct CoachTag: View {
    @Environment(\.sceneTheme) private var theme

    public init() {}

    public var body: some View {
        Text("教练", bundle: .module)
            .typeStyle(TypeRamp.label)
            .foregroundStyle(Color(role: .fgOnInk, in: theme))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.xs - Space.xxs / 2)
            .frame(height: Self.height)
            .background(
                Color(role: .bgInk, in: theme), in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
            )
    }

    /// The approved design's 18 points.
    private static let height: Double = 18
}
#endif
