import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Every bundled coach builds, plays each move from rest, and stays on the canvas.
@Test func everyCoachPlaysEveryMove() throws {
    #expect(CoachCharacter.bundled == ["xiaohun"])
    for coach in CoachCharacter.bundled {
        let figure = try CoachCharacter.figure(coach)
        for move in CoachCharacter.Move.allCases {
            let clip = try CoachCharacter.clip(move, coach: coach)
            let bound = try figure.bind(clip)
            #expect(clip.loops == (move != .cheer), "\(coach) \(move)")
            expectOnCanvas(figure, bound, for: clip.duration, "\(coach) \(move)")
        }
    }
}

/// 毛头 is a member-style cat in its own jacket and whistle, moving as a deadpan cat.
@Test func maotouWearsItsOwnLook() throws {
    let look = try CoachCharacter.look("xiaohun")
    #expect(look.persona == .deadpan)
    #expect(look.species == "cat")
    #expect(look.outfit.variants["body"] == "maotou")
    #expect(look.outfit.variants["top"] == "coach-jacket")
    #expect(look.outfit.variants["acc"] == "coach-gear")
    #expect(look.outfit.colors["bottom"] == RGBAColor(hex: "#2A2D36"))
}

/// A coach's own parts never show in the character editor's lists.
@Test func coachPartsStayOutOfTheEditor() {
    #expect(!PlaceholderCharacter.variants(for: "body").contains("maotou"))
    #expect(!PlaceholderCharacter.variants(for: "top").contains("coach-jacket"))
    #expect(!PlaceholderCharacter.variants(for: "acc").contains("coach-gear"))
}

@Test func aCoachWithoutArtHasNone() {
    #expect(!CoachCharacter.exists("not-a-coach"))
    #expect(throws: AvatarError.self) { try CoachCharacter.figure("not-a-coach") }
}
