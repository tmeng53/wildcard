#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Sign-up's floor, under the open screen's crowd and 上场: light grey, with the brand's graphite
/// and white stripe along its top and faint tiles, as on the website. Sign-up is a brand screen,
/// so it stands on no scene's floor.
struct BrandFloor: View {
    let theme: SceneTheme
    /// The tiles' side, in points.
    private static let tile = 65.0
    /// The first row of tiles, under the floor's stripe.
    private static let firstRow = 64.0

    var body: some View {
        ZStack(alignment: .top) {
            Color(role: .bgBrandFloor, in: theme)
            Canvas { context, size in
                var path = Path()
                for column in stride(from: Self.tile, to: size.width, by: Self.tile) {
                    path.move(to: CGPoint(x: column, y: 0))
                    path.addLine(to: CGPoint(x: column, y: size.height))
                }
                for row in stride(from: Self.firstRow, to: size.height, by: Self.tile) {
                    path.move(to: CGPoint(x: 0, y: row))
                    path.addLine(to: CGPoint(x: size.width, y: row))
                }
                context.stroke(path, with: .color(Color(role: .borderBrandFloor, in: theme)), lineWidth: 1.5)
            }
            VStack(spacing: 0) {
                Color(role: .bgBrand, in: theme).frame(height: 4)
                Color(role: .fgOnBrand, in: theme).frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
