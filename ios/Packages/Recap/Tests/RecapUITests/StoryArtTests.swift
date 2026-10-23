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

/// Every story clip, start to end, stays inside the area a story character is drawn in, so
/// nothing is cut off. Curves stay inside their control points, so those are checked too.
@Test(arguments: Persona.allCases)
func everyStoryClipStaysInItsRoom(persona: Persona) throws {
    let clips: [StoryClip] =
        AwardMove.allCases.map(StoryClip.award) + [
            .eat(.healthy), .eat(.cheat), .tossFlyer, .tossThrower, .stackTop, .stackBottom,
        ]
    // The widest bodies: a bear's ears, a lop's ears, a cat's tail.
    let looks =
        [PlaceholderCharacter.lifter]
        + ["bear", "lop", "cat"].map { body in
            var look = PlaceholderCharacter.lifter
            look.variants["body"] = body
            return look
        }
    for look in looks {
        for clip in clips {
            let figure = try PlaceholderCharacter.figure(wearing: clip.dressing(look))
            let bound = try figure.bind(clip.art(persona: persona, species: nil))
            var regalia = Regalia(medal: true, crown: 0)
            for frame in 0...Int(bound.clip.duration * 25) {
                var pose = figure.pose(bound, at: Double(frame) / 25)
                // Only the champion wears the crown, through the toss and their award move; it
                // drops in the first second, and one lying flat wears it already down.
                switch clip {
                case .award(.flat): regalia.crown = 1
                case .award, .tossFlyer: regalia.crown = min(Double(frame) / 25, 1)
                default: regalia.crown = nil
                }
                regalia.dress(&pose, on: figure)
                for (part, placement) in zip(figure.parts, figure.layout(pose)) where placement.opacity > 0 {
                    for shape in part.art.flatMap(\.shapes) {
                        let margin = (shape.stroke?.width ?? 0) / 2
                        for point in shape.path.flatMap(\.points).map(placement.transform.apply(to:)) {
                            #expect(
                                point.x - margin >= StoryRoom.minX && point.x + margin <= StoryRoom.maxX
                                    && point.y - margin >= StoryRoom.minY && point.y + margin <= StoryRoom.maxY,
                                "\(clip) \(persona): \(part.id) at (\(point.x), \(point.y))")
                        }
                    }
                }
            }
        }
    }
}

extension PathElement {
    fileprivate var points: [Point] {
        switch self {
        case .move(let point), .line(let point): [point]
        case .quadCurve(let end, let control): [end, control]
        case .curve(let end, let control1, let control2): [end, control1, control2]
        case .close: []
        }
    }
}
