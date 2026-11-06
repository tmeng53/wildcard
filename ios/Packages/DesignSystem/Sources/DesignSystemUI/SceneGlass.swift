#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Light Liquid Glass for what floats on a home scene (a speech bubble, the squad card and its
/// folded capsule): the system's `glassEffect`, tinted white so ink words read on any scene.
enum SceneGlass {
    /// How much white the glass carries: enough that a coloured scene (the red track) doesn't dye
    /// it and ink words read at night, little enough that the scene still shows through.
    static let tint = 0.72
}

extension View {
    /// This view on scene glass in `shape`; `interactive` glass reacts to a touch, for a control.
    func sceneGlass(in shape: some Shape, theme: SceneTheme, interactive: Bool = false) -> some View {
        let glass = Glass.regular.tint(Color(role: .bgCanvas, in: theme).opacity(SceneGlass.tint))
        return glassEffect(interactive ? glass.interactive() : glass, in: shape)
    }
}
#endif
