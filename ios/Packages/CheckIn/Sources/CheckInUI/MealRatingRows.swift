#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 这顿怎么样 on a meal's compose page: a row of 软糖星 each for 健康 and 好吃, both optional,
/// with or without a place (Tracy, 2026-11-12: every meal can be rated, home cooking too). The
/// meal is posted with its rating once both are picked.
struct MealRatingRows: View {
    @Binding var healthy: Int?
    @Binding var tasty: Int?
    @Environment(\.sceneTheme) private var theme

    /// The design's star, bigger than a list's so each is easy to hit.
    private static let star: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(Text(copy: "这顿怎么样", bundle: .module))
            row(Text(copy: "健康", bundle: .module), score: $healthy, id: "compose.healthy")
            row(Text(copy: "好吃", bundle: .module), score: $tasty, id: "compose.tasty")
        }
    }

    private func row(_ label: Text, score: Binding<Int?>, id: String) -> some View {
        HStack(spacing: Space.s) {
            label
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Spacer(minLength: 0)
            StarRating(rating: score.wrappedValue ?? 0, size: Self.star) { score.wrappedValue = $0 }
                .accessibilityIdentifier(id)
        }
        .frame(minHeight: Sizing.minimumTapTarget)
    }
}
#endif
