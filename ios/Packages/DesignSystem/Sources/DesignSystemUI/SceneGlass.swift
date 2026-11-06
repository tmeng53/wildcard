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

/// Which glass this glass morphs into when one view takes another's place, inside a
/// `GlassEffectContainer`: the same `id` in the same namespace (the squad card and its capsule).
public struct GlassMorph {
    let id: String
    let namespace: Namespace.ID

    public init(_ id: String, in namespace: Namespace.ID) {
        self.id = id
        self.namespace = namespace
    }
}

extension View {
    /// This view on scene glass in `shape`; `interactive` glass reacts to a touch, for a control.
    @ViewBuilder
    func sceneGlass(
        in shape: some Shape, theme: SceneTheme, interactive: Bool = false, morph: GlassMorph? = nil
    ) -> some View {
        let glass = Glass.regular.tint(Color(role: .bgCanvas, in: theme).opacity(SceneGlass.tint))
        let glassy = glassEffect(interactive ? glass.interactive() : glass, in: shape)
        // The id goes on the view that carries the glass, or the system has nothing to morph.
        if let morph { glassy.glassEffectID(morph.id, in: morph.namespace) } else { glassy }
    }
}
#endif
