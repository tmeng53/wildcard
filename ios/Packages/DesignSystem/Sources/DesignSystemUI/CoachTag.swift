#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// 「教练」: the graphite tag beside the AI coach's name wherever it speaks (its 战术板 line, its
/// replies), so nobody takes its words for a teammate's.
public struct CoachTag: View {
    /// `regular` over the scene (the 战术板, the sideline's bubble); `small` among a post's
    /// comments and reactions, as the approved badge design has it.
    public enum Size: Sendable {
        case regular
        case small

        public var height: Double {
            switch self {
            case .regular: 18
            case .small: 16
            }
        }
    }

    @Environment(\.sceneTheme) private var theme
    private let size: Size

    public init(_ size: Size = .regular) {
        self.size = size
    }

    public var body: some View {
        Text("教练", bundle: .module)
            .typeStyle(TypeRamp.label)
            .foregroundStyle(Color(role: .fgOnInk, in: theme))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.xs - Space.xxs / 2)
            .frame(height: size.height)
            .background(
                Color(role: .bgInk, in: theme), in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
            )
    }
}
#endif
