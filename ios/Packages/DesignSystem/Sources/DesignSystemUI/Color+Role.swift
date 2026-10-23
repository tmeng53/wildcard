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
    public init(role: ColorRole, in theme: SceneTheme, contrast: ColorSchemeContrast = .standard) {
        self.init(role.color(in: theme, contrast: contrast == .increased ? .increased : .standard))
    }
}

extension EnvironmentValues {
    /// The scene the squad picked. Views read it to color their accent roles.
    @Entry public var sceneTheme: SceneTheme = .pool
    /// Whose colour primary buttons and selection marks wear here. A brand screen sets `.brand`
    /// once at its root (`.accentTone(.brand)`); everything inside follows.
    @Entry public var accentTone: AccentTone = .scene
}

extension View {
    /// Dresses primary buttons, selection marks, switches and the text cursor inside in the brand's
    /// colour (`.brand`) or the scene's (`.scene`).
    public func accentTone(_ tone: AccentTone) -> some View {
        environment(\.accentTone, tone)
    }
}
#endif
