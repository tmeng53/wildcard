#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarLooks
@testable import AvatarUI
import Foundation
import SwiftUI
import Testing

/// The preview of 排队入场: five in a row above eight walking through, as the 战报's last page
/// shows them, on the pool's sky.
extension CharacterPreviewTests {
    /// `13-lineup.gif`.
    func writeLineup(to url: URL) throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        func squad(_ count: Int) throws -> [CharacterPlayer] {
            try (0..<count).map { index in
                let persona = Persona.allCases[index % Persona.allCases.count]
                return try CharacterPlayer(
                    figure: PlaceholderCharacter.figure(wearing: Looks.squad[index % Looks.squad.count]),
                    idle: PlaceholderCharacter.clip("idle", persona: persona),
                    now: start.addingTimeInterval(-Double(index) * 0.6))
            }
        }
        let (five, eight) = (try squad(5), try squad(8))
        let strip = CGSize(width: 390, height: 96)
        let sky = Color(.sRGB, red: 0xCD / 255, green: 0xEB / 255, blue: 0xF1 / 255, opacity: 1)
        try writeGIF(
            frames(seconds: 6, fps: 25) { time in
                let date = start.addingTimeInterval(time)
                let view = VStack(spacing: 12) {
                    LineupFrame(players: five, size: strip, date: date, time: time, still: false)
                    LineupFrame(players: eight, size: strip, date: date, time: time, still: false)
                }
                .padding(.vertical, 12)
                .clipped()
                .background(sky)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                return try #require(renderer.cgImage)
            },
            fps: 25, to: url)
    }
}
#endif
