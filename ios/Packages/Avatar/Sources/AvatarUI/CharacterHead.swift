#if canImport(SwiftUI)
import SwiftUI

/// A member's head for a ring or a badge, standing still: framed on the face, so every
/// species shows its eyes and mouth at any size (tall ears and hair may be trimmed).
/// Size it with a frame; it fills a square.
public struct CharacterHead: View {
    let player: CharacterPlayer

    public init(player: CharacterPlayer) {
        self.player = player
    }

    public var body: some View {
        let frame = player.restFrame
        CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.face)
            .aspectRatio(1, contentMode: .fit)
            // The figure is decoration; who it is is said by the screen around it.
            .accessibilityHidden(true)
    }

    /// The face on the rig's 240 by 320 canvas: the head (78 to 217 down) with the eyes (158)
    /// and mouth (185) a little below the middle, as on a sticker.
    static let face = CGRect(x: 40, y: 74, width: 160, height: 160)
}
#endif
