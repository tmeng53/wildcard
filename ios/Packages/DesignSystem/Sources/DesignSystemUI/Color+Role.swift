#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

extension Color {
    public init(_ rgb: SRGBColor) {
        self.init(
            .sRGB,
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255,
            opacity: 1
        )
    }

    /// A role's color in a scene. Neutral roles ignore the scene.
    public init(role: ColorRole, in theme: SceneTheme) {
        self.init(role.color(in: theme))
    }
}

extension EnvironmentValues {
    /// The scene the squad picked. Views read it to color their accent roles.
    @Entry public var sceneTheme: SceneTheme = .pool
}
#endif
