#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A stand-in head for the ring demo; the app passes the character.
struct GuideFace: View {
    @Environment(\.sceneTheme) private var theme
    let index: Int

    var body: some View {
        Image(
            systemName: ["face.smiling", "pawprint.fill", "hare.fill", "face.smiling.inverse", "cat.fill", "dog.fill"][
                index % 6]
        )
        .font(.system(size: Sizing.characterHead * 0.55))
        .foregroundStyle(Color(role: .fgMuted, in: theme))
    }
}

/// Three stand-in heads overlapping, for the style guide's folded capsule.
struct GuideHeads: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: -Space.xxs) {
            ForEach(0..<SquadCapsuleLayout.heads, id: \.self) { index in
                GuideFace(index: index)
                    .frame(width: SquadCapsuleLayout.head, height: SquadCapsuleLayout.head)
                    .background(Color(role: .bgSubtle, in: theme), in: Circle())
            }
        }
    }
}
#endif
