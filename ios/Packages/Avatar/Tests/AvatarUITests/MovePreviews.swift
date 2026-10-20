#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarLooks
import Contracts
import Foundation
import SwiftUI
import Testing

/// The previews of moves that change the character: sport kits and the 上场 entrance.
extension CharacterPreviewTests {
    /// The lifter (and a cat beside it) picking each sport in turn, every 2 s: a quick turn and
    /// hop into the kit, then the sport's move.
    func writeKits(to url: URL) throws {
        let kits = try PlaceholderCharacter.sportKits()
        let turn = try PlaceholderCharacter.turn()
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
                    turningOut: try look.figure.bind(turn.out), turningIn: try look.figure.bind(turn.in),
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

    /// 上场 on the stage it crosses: the lifter runs in from the right, skids, crouches, jumps
    /// with a spin and lands, then cheers its welcome.
    func writeEntrance(to url: URL) throws {
        let look = try Frame(outfit: PlaceholderCharacter.lifter)
        let figure = look.figure
        var entering = Performance(
            figure: figure, idle: try figure.bind(PlaceholderCharacter.clip("idle", persona: .showoff)))
        let entrance = try figure.bind(PlaceholderCharacter.entrance())
        entering.play(entrance, at: 0.3)
        let landed = 0.3 + entrance.clip.duration
        var welcoming = entering
        welcoming.play(try figure.bind(PlaceholderCharacter.clip("welcome", persona: .showoff)), at: landed)
        let stage = CGRect(x: -60, y: -380, width: 1280, height: 710)
        try writeGIF(
            frames(seconds: 5.5, fps: 20) { time in
                let performance = time < landed ? entering : welcoming
                return try look.render(
                    image: performance.pose(at: time), scale: 0.4, background: Self.mist, crop: stage)
            },
            fps: 20, to: url)
    }
}
#endif
