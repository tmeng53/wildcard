import AvatarArt
import AvatarDomain
import RecapDomain
import Testing

@testable import RecapUI

/// Every clip the story plays has its own art now: only the cheer, the pair-only stack and a
/// sport without a kit fall back to the persona's cheer.
@Test(arguments: Persona.allCases)
func everyStoryClipPlaysItsOwnArt(persona: Persona) throws {
    let cheer = try PlaceholderCharacter.clip("cheer", persona: persona, species: nil)
    let clips: [StoryClip] =
        AwardMove.allCases.map(StoryClip.award) + [
            .eat(.healthy), .eat(.cheat), .tossFlyer, .tossThrower, .stackTop, .stackBottom, .sport(nil),
        ]
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    for clip in clips {
        let art = try clip.art(persona: persona, species: nil)
        _ = try figure.bind(art)
        let fallsBack = [StoryClip.award(.cheer), .award(.stack), .sport(nil)].contains(clip)
        #expect((art == cheer) == fallsBack, "\(clip)")
    }
    #expect(try StoryClip.award(.flat).art(persona: persona, species: nil).name == "flat")
    #expect(try StoryClip.stackTop.art(persona: persona, species: nil).name == "stack-top")
}

/// A meal holds its food, the bowl for 健康餐 and the boba for 坦白放纵餐; nothing else changes
/// the look.
@Test func aMealHoldsItsFood() {
    let look = PlaceholderCharacter.lifter
    #expect(StoryClip.eat(.healthy).dressing(look).variants["food"] == "bowl")
    #expect(StoryClip.eat(.cheat).dressing(look).variants["food"] == "boba")
    #expect(StoryClip.award(.pump).dressing(look) == look)
}

/// The medal and the crown are the rig's own parts: hidden until worn, the medal on, the crown
/// out of sight above the head until it lands.
@Test func regaliaShowsTheRigsAwardParts() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let medal = try #require(figure.parts.firstIndex { $0.id == "medal" })
    let award = try #require(figure.parts.firstIndex { $0.id == "award" })
    let rest = figure.restPose
    #expect(rest.parts[medal].opacity == 0 && rest.parts[award].opacity == 0)

    var none = rest
    Regalia.none.dress(&none, on: figure)
    #expect(none == rest)

    var dropping = rest
    Regalia(medal: true, crown: 0).dress(&dropping, on: figure)
    #expect(dropping.parts[medal].opacity == 1)
    #expect(dropping.parts[award].opacity == 0 && dropping.parts[award].y == -260)

    var landed = rest
    Regalia(medal: false, crown: 1).dress(&landed, on: figure)
    #expect(landed.parts[medal].opacity == 0)
    #expect(landed.parts[award].opacity == 1 && landed.parts[award].y == 0)
}
