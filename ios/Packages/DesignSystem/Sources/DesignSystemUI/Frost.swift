#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

extension View {
    /// Plain frosted material with a white wash over it, behind the view: no rim, glow or
    /// highlight. For navigation and controls that float over the scene, never content.
    public func frosted<S: Shape>(white fill: Double, in shape: S) -> some View {
        background {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(Palette.white).opacity(fill)))
        }
    }
}
#endif
