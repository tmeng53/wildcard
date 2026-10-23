#if canImport(SwiftUI)
import AvatarArt
import AvatarUI
import SwiftUI
import Testing

/// The preview of the heads the squad card's rings show.
extension CharacterPreviewTests {
    /// `14-heads.png`: every body's `CharacterHead` in a circle, as a ring shows it. A row per
    /// size, from the squad card's narrow-phone ring up to a large badge, drawn at 3x like a phone.
    func writeHeads(to url: URL) throws {
        let idle = try PlaceholderCharacter.clip("idle", persona: .deadpan)
        let players = try PlaceholderCharacter.variants(for: "body").map { body in
            var outfit = PlaceholderCharacter.lifter
            outfit.variants["body"] = body
            if body != "peach" { outfit.variants["hair"] = nil }
            return try CharacterPlayer(figure: PlaceholderCharacter.figure(wearing: outfit), idle: idle)
        }
        let rows = try [22.0, 28, 44, 84].map { size in
            try sideBySide(
                players.map { player in
                    let view = CharacterHead(player: player)
                        .frame(width: size, height: size)
                        .background(Color(.sRGB, red: 0xE4 / 255, green: 0xE8 / 255, blue: 0xEE / 255, opacity: 1))
                        .clipShape(Circle())
                        .padding(size / 4)
                        .background(Self.mist)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 3
                    return try #require(renderer.cgImage)
                })
        }
        try writePNG(stacked(rows), to: url)
    }
}
#endif
