#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The 软糖星 in the style guide: five stars to tap, the first three lit.
struct StarGuide: View {
    @State private var stars = 3

    var body: some View {
        GuideGroup(Text(copy: "星星：软糖星，点几颗就是几分", bundle: .module)) {
            StarRating(rating: stars, size: 36) { stars = $0 }
                .accessibilityIdentifier("styleguide.stars")
        }
    }
}
#endif
