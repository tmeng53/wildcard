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
        InkTag(Text(copy: "教练", bundle: .module), height: size.height)
    }
}

/// A word on a graphite tag, in `CoachTag`'s shape: 「教练」 by the coach's name, 「NEW」 on a
/// piece the member hasn't tapped since it came in.
public struct InkTag: View {
    @Environment(\.sceneTheme) private var theme
    private let word: Text
    private let height: Double

    /// The small tag, as among a post's comments, unless `height` says otherwise.
    public init(_ word: Text, height: Double = CoachTag.Size.small.height) {
        (self.word, self.height) = (word, height)
    }

    /// 「NEW」.
    public static var new: InkTag { InkTag(Text(copy: "NEW", bundle: .module)) }

    public var body: some View {
        word
            .typeStyle(TypeRamp.label)
            .foregroundStyle(Color(role: .fgOnInk, in: theme))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.xs - Space.xxs / 2)
            .frame(height: height)
            .background(
                Color(role: .bgInk, in: theme), in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
            )
    }
}
#endif
