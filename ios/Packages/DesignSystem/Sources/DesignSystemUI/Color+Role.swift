#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

extension Color {
    public init(_ rgb: RGBColor) {
        self.init(
            .sRGB,
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255,
            opacity: 1
        )
    }

    public init(role: ColorRole) {
        self.init(role.color)
    }
}
#endif
