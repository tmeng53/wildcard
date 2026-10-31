#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import SwiftUI

/// A whole page's loader (loader design A, 2026-10-24): the character jogging in place, with no
/// words. Put it in a `loadingCover`, which waits before it shows and keeps it long enough. The
/// stand-in lifter runs until a screen knows whose look to show. With Reduce Motion on, the
/// character stands and breathes instead.
public struct LoadingCharacter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let look: Outfit
    @State private var player: CharacterPlayer?

    public init(look: Outfit = PlaceholderCharacter.lifter) {
        self.look = look
    }

    public var body: some View {
        Group {
            if let player { CharacterView(player: player) }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .task(id: reduceMotion) {
            let move: Clip?
            if reduceMotion {
                move = try? PlaceholderCharacter.clip("idle", persona: .deadpan)
            } else {
                move = try? PlaceholderCharacter.jogging()
            }
            guard let move else { return }
            player = try? CharacterPlayer(figure: PlaceholderCharacter.figure(wearing: look), idle: move)
        }
        .accessibilityHidden(true)
    }

    /// The character at the size the state screens show it, in points.
    static let size = CGSize(width: 120, height: 160)
}
#endif
