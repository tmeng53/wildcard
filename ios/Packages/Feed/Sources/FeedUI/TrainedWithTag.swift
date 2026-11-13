#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 一起练 on a 训练's card (approved 2026-11-10): a capsule with the squadmates' heads and 「和 小鱼、
/// Kiki」, or 「和 小鱼 等 3 人」 past two, 我 for the viewer.
struct TrainedWithTag: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let members: [MemberID]

    var body: some View {
        HStack(spacing: Space.xxs) {
            HStack(spacing: -Self.overlap) {
                ForEach(members.prefix(Self.heads), id: \.self) { member in
                    MemberHead(player: model.head(of: member), size: Self.head)
                }
            }
            words
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
        }
        .padding(.leading, Space.xxs)
        .padding(.trailing, Space.xs)
        .padding(.vertical, Space.xxs / 2)
        .background(Color(role: .bgSubtle, in: theme), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("post.trainedWith")
    }

    private var words: Text {
        let names = members.map(model.displayName(of:))
        return switch names.count {
        case 0: Text(verbatim: "")
        case 1: Text(copy: "和 \(names[0])", bundle: .module)
        case 2: Text(copy: "和 \(names[0])、\(names[1])", bundle: .module)
        default: Text(copy: "和 \(names[0]) 等 \(names.count) 人", bundle: .module)
        }
    }

    private static let heads = 3
    private static let head: Double = 20
    private static let overlap: Double = 6
}
#endif
