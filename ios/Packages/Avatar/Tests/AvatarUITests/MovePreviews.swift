#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarLooks
import Contracts
import Foundation
import SwiftUI
import Testing

/// The previews of moves that change the character: sport kits, the 上场 entrance, 我's
/// typing at the laptop and crying on 注销账号, and the props' moves in the editor.
extension CharacterPreviewTests {
    /// `09-sport-kits.gif`, `10-entrance.gif`, `11-typing.gif`, `12-teary.gif` and
    /// `14-prop-moves.gif`.
    func writeMoves(to folder: URL) throws {
        try writeKits(to: folder.appendingPathComponent("09-sport-kits.gif"))
        try writeEntrance(to: folder.appendingPathComponent("10-entrance.gif"))
        try writeMeMove(typing: true, to: folder.appendingPathComponent("11-typing.gif"))
        try writeMeMove(typing: false, to: folder.appendingPathComponent("12-teary.gif"))
        try writePropMoves(to: folder.appendingPathComponent("14-prop-moves.gif"))
    }

    /// Each prop the editor offers, held by the lifter and the cat, playing its move once every
    /// 2.5 s from a still stand, as the editor plays it on every change.
    func writePropMoves(to url: URL) throws {
        let props = try PlaceholderCharacter.editorChoices().props
        let stages = try props.flatMap { prop in
            try [PlaceholderCharacter.lifter, Looks.cat].map { outfit in
                var held = outfit
                held.variants["prop"] = prop
                let look = try Frame(outfit: held)
                return (look, try look.figure.bind(try #require(try PlaceholderCharacter.propMove(for: held))))
            }
        }
        try writeGIF(
            frames(seconds: 5, fps: 20) { time in
                try sideBySide(
                    stages.map { look, move in
                        try look.render(
                            image: look.figure.pose(move, at: time.truncatingRemainder(dividingBy: 2.5)), scale: 1,
                            background: Self.mist)
                    })
            },
            fps: 20, to: url)
    }

    /// The lifter (and a cat beside it) picking each sport in turn, every 2 s: a hop into the
    /// kit, then the sport's move.
    func writeKits(to url: URL) throws {
        let kits = try PlaceholderCharacter.sportKits()
        let hop = try PlaceholderCharacter.kitHop()
        let sports: [Sport] = [.swim, .run, .strength, .tennis, .climb, .yoga]
        let cast: [(Persona, Outfit)] = [(.energetic, PlaceholderCharacter.lifter), (.deadpan, Looks.cat)]
        // A performance acts on what is asked of it at once, so each pick is a performance of its
        // own, on stage from the moment it's made.
        var stages: [(looks: [Frame], picks: [(from: Double, performance: Performance)])] = []
        for (persona, outfit) in cast {
            var looks = [try Frame(outfit: outfit)]
            var performance = Performance(
                figure: looks[0].figure,
                idle: try looks[0].figure.bind(PlaceholderCharacter.clip("idle", persona: persona)))
            var picks = [(from: 0.0, performance: performance)]
            for (index, sport) in sports.enumerated() {
                let kit = kits.kit(for: .sport(sport))
                let look = try Frame(outfit: kit.dress(outfit))
                looks.append(look)
                let time = 0.5 + Double(index) * 2
                performance.change(
                    into: look.figure,
                    idle: try look.figure.bind(PlaceholderCharacter.move(for: kit, persona: persona)),
                    leaving: try look.figure.bind(hop.out), arriving: try look.figure.bind(hop.in),
                    at: time)
                picks.append((time, performance))
            }
            stages.append((looks, picks))
        }
        try writeGIF(
            frames(seconds: 12.5, fps: 20) { time in
                try sideBySide(
                    stages.map { stage in
                        let performance = try #require(stage.picks.last { $0.from <= time }).performance
                        let figure = performance.figure(at: time)
                        let look = try #require(stage.looks.first { $0.figure == figure })
                        return try look.render(image: performance.pose(at: time), scale: 1, background: Self.mist)
                    })
            },
            fps: 20, to: url)
    }

    /// 上场 on the stage it crosses: the lifter runs in from the right, skids, crouches,
    /// star-jumps and lands, then cheers its welcome.
    func writeEntrance(to url: URL) throws {
        let look = try Frame(outfit: PlaceholderCharacter.lifter)
        let figure = look.figure
        var entering = Performance(
            figure: figure, idle: try figure.bind(PlaceholderCharacter.clip("idle", persona: .showoff)))
        let entrance = try figure.bind(PlaceholderCharacter.entrance())
        // The stage waits a beat with the lifter still off it: its clock starts 0.3 s in.
        entering.play(entrance, at: 0, blending: false)
        let landed = entrance.clip.duration
        var welcoming = entering
        welcoming.play(try figure.bind(PlaceholderCharacter.clip("welcome", persona: .showoff)), at: landed)
        // The sign-up design's stage: the phone's width at the design's 0.28 scale, the landing spot
        // in the middle, and room above for the jump. Its right edge is left of where the run starts.
        let stage = CGRect(x: -576, y: -380, width: 1392, height: 710)
        #expect(stage.maxX < PlaceholderCharacter.entranceStartsRightOf)
        try writeGIF(
            frames(seconds: 5.5, fps: 20) { frame in
                let time = max(0, frame - 0.3)
                let performance = time < landed ? entering : welcoming
                return try look.render(
                    image: performance.pose(at: time), scale: 0.4, background: Self.mist, crop: stage)
            },
            fps: 20, to: url)
    }

    /// The squad at 我's desk typing, or crying as on 注销账号, each look in a persona of its
    /// own, two loops long.
    func writeMeMove(typing: Bool, to url: URL) throws {
        let cast = Array(zip(Looks.squad, [Persona.deadpan, .energetic, .drama, .shy]))
        let stages = try cast.map { outfit, persona in
            let look = try Frame(outfit: typing ? PlaceholderCharacter.atDesk(outfit) : outfit)
            let clip =
                try typing
                ? PlaceholderCharacter.typing(persona: persona) : PlaceholderCharacter.teary(persona: persona)
            return (look, try look.figure.bind(clip))
        }
        try writeGIF(
            frames(seconds: typing ? 8 : 6.4, fps: 20) { time in
                try sideBySide(
                    stages.map { look, move in
                        try look.render(image: look.figure.pose(move, at: time), scale: 1, background: Self.mist)
                    })
            },
            fps: 20, to: url)
    }
}
#endif
