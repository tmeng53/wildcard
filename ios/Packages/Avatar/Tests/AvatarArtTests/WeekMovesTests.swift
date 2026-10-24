import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import Testing

private let look = Outfit(["body": "peach", "hat": "cap"])

/// The poster's character puts on the kit of the sport planned most and loops its move.
@Test func aWeeksCharacterLoopsItsMostPlannedSport() throws {
    let days: [PlanDay] = [
        .train(.sport(.swim)), .rest, .train(.sport(.run)), .train(.sport(.swim)), .rest, .rest, .rest,
    ]
    let (outfit, clip) = try PlaceholderCharacter.weekLoop(for: days, look: look, persona: .drama)
    #expect(outfit.variants["hat"] == "swimcap")
    #expect(
        clip
            == (try PlaceholderCharacter.move(
                for: try PlaceholderCharacter.sportKits().kit(for: .sport(.swim)), persona: .drama)))
    #expect(clip.loops)
}

/// Training with no sport named warms up, in the character's own clothes.
@Test func aWeekOfUnnamedTrainingWarmsUp() throws {
    let days: [PlanDay] = [.train(nil), .train(nil), .rest, .rest, .rest, .rest, .rest]
    let (outfit, _) = try PlaceholderCharacter.weekLoop(for: days, look: look, persona: .drama)
    #expect(outfit == look)
}

/// A week of rest sits on the floor in the character's own look.
@Test func aWeekOfRestSitsDown() throws {
    let (outfit, clip) = try PlaceholderCharacter.weekLoop(
        for: Array(repeating: .rest, count: 7), look: look, persona: .drama)
    #expect(outfit == look)
    #expect(clip == (try PlaceholderCharacter.sitting(persona: .drama)))
}
