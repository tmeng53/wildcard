import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Every change of an arm's depth happens while its forearm is clear of the body, so it can't be
/// seen: where the forearm (the only part drawn in front, `Figure.forearm`) covers the torso, what
/// is worn over it or the other arm, front and behind look different, and a swap there jumps
/// however it is timed. Every move and clip is played as the app plays it (`Performance`), on
/// each species' body, over the persona's idle with that species' moves: from two moments of the
/// idle, blending in, through to the blend back to idle (a loop is ended by the next `play`). At
/// every frame where an arm changes depth, and the frame before, the forearm may overlap what
/// lies between its two copies by at most 16 square points: a sliver along an outline, where the
/// two drawings already agree.
@Test(arguments: [("cat", "warmup-tee"), ("bear", "warmup-tee"), ("cat", "warmup-long")])
func everyArmDepthSwapHappensClearOfTheBody(body: String, top: String) throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/AvatarArt/Placeholder")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var swaps = 0
    for case let url as URL in files where url.pathExtension == "json" {
        // The path under Placeholder, from its components: macOS's enumerator hands back resolved
        // paths, without the root's "../..", so cutting the root's path off would leave it whole.
        let name =
            "/"
            + url.standardizedFileURL.pathComponents.drop { $0 != "Placeholder" }.dropFirst()
            .joined(separator: "/")
        guard ["/moves/", "/clips/"].contains(where: name.hasPrefix),
            let clip = try? Clip.decode(Data(contentsOf: url))
        else { continue }
        let file = url.deletingPathExtension().lastPathComponent
        // A persona's own clips, reactions and meals play only for it; the rest for any.
        let own = Persona.allCases.filter { name.contains("/\($0.rawValue)/") || file.hasSuffix("-\($0.rawValue)") }
        // Clips, meals and the entrance play as drawn; every other move at the persona's tempo.
        let asDrawn =
            name.hasPrefix("/clips/") || name.contains("/checkins/") && !name.contains("doze")
            || file == "entrance"
        var look: [Slot: String] = ["body": body, "top": top, "bottom": "warmup-shorts"]
        // A prop's move is played holding it.
        look["prop"] = name.contains("/props/") ? file : nil
        let outfit = Outfit(look)
        let figure = try PlaceholderCharacter.figure(wearing: outfit)
        for persona in own.isEmpty ? Persona.allCases : own {
            let idle = try figure.bind(
                PlaceholderCharacter.clip("idle", persona: persona, species: PlaceholderCharacter.species(of: outfit)))
            let move = try figure.bind(asDrawn ? clip : clip.atTempo(persona.accentTempo))
            for start in [0.5, 2.9] {
                let end = start + move.clip.duration * (move.clip.loops ? 1.5 : 1)
                // A loop goes on until the next play.
                let plays = [(move, start)] + (move.clip.loops ? [(idle, end)] : [])
                let performance = Performance(figure: figure, idle: idle)
                for (frame, pair) in swapsOfDepth(in: performance, playing: plays, through: end + 0.5) {
                    swaps += 1
                    let shown = try max(
                        overlap(of: pair.arm, in: figure, pair.after), overlap(of: pair.arm, in: figure, pair.before))
                    #expect(
                        shown <= 16,
                        "\(name) as \(persona) on \(body) from \(start)s swaps \(pair.arm) at frame \(frame) over \(shown) pt²"
                    )
                }
            }
        }
    }
    #expect(swaps > 200)
}

/// No idle, with any species' moves on top, holds a forearm over the body, so a move can bring an
/// arm in front, or hand it back behind, right as it blends from or back to idle. Long sleeves
/// too: their tops carry the shoulder, and the idles hold the arms a little out from the body.
@Test(arguments: ["peach", "cat", "corgi", "lop", "bear"], topsWithSleeves)
func noIdleHoldsAnArmOverTheBody(body: String, top: String) throws {
    let outfit = Outfit(["body": body, "top": top, "bottom": "warmup-shorts"])
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    for persona in Persona.allCases {
        let idle = try figure.bind(
            PlaceholderCharacter.clip("idle", persona: persona, species: PlaceholderCharacter.species(of: outfit)))
        for frame in 0...Int(idle.clip.duration / persona.accentTempo * 30) {
            let pose = figure.pose(idle, at: Double(frame) / 30)
            for arm: PartID in ["armL", "armR"] {
                let shown = try overlap(of: arm, in: figure, pose)
                #expect(
                    shown <= 4,
                    "\(persona)'s idle on \(body) in \(top) holds \(arm) over the body at frame \(frame): \(shown) pt²")
            }
        }
    }
}

/// A sport's move is an idle too: on 今天 a member who trained stands in their kit, and a tap
/// plays their signature move (`PlaceholderCharacter.signatureMove`), or a cheer, and hands back
/// to the kit's move, which may hold an arm anywhere. Each swap stays clear of the body there too.
@Test(arguments: Persona.allCases)
func everyArmDepthSwapOverAKitHappensClearOfTheBody(persona: Persona) throws {
    var swaps = 0
    for kit in try PlaceholderCharacter.sportKits().kits {
        for body in ["peach", "bear"] {
            let outfit = kit.dress(Outfit(["body": body, "top": "warmup-tee", "bottom": "warmup-shorts"]))
            let figure = try PlaceholderCharacter.figure(wearing: outfit)
            let idle = try figure.bind(PlaceholderCharacter.move(for: kit, persona: persona))
            let moves = [
                try PlaceholderCharacter.signatureMove(wearing: outfit, persona: persona),
                try PlaceholderCharacter.clip(
                    "cheer", persona: persona, species: PlaceholderCharacter.species(of: outfit)),
            ]
            for move in try moves.map(figure.bind) {
                for start in [0.37, 1.3, 2.05] {
                    let performance = Performance(figure: figure, idle: idle)
                    for (frame, pair) in swapsOfDepth(
                        in: performance, playing: [(move, start)], through: start + move.clip.duration + 0.8)
                    {
                        swaps += 1
                        let shown = try max(
                            overlap(of: pair.arm, in: figure, pair.after),
                            overlap(of: pair.arm, in: figure, pair.before))
                        #expect(
                            shown <= 16,
                            "\(move.clip.name) over \(kit.id) as \(persona) on \(body) from \(start)s swaps \(pair.arm) at frame \(frame) over \(shown) pt²"
                        )
                    }
                }
            }
        }
    }
    #expect(swaps > 0)
}

/// Each frame, at 60 a second, where an arm's front copy shows or hides, with the poses either
/// side of it, as a performance over its idle plays each clip at its time (as the app does: a
/// performance only ever goes forward), from the first play until `end`.
private func swapsOfDepth(in idle: Performance, playing plays: [(clip: BoundClip, at: Double)], through end: Double)
    -> [(frame: Int, pair: (arm: PartID, before: Pose, after: Pose))]
{
    var stages = [(from: -Double.infinity, performance: idle)]
    for play in plays {
        var next = stages[stages.count - 1].performance
        next.play(play.clip, at: play.at)
        stages.append((play.at, next))
    }
    func pose(at time: Double) -> Pose {
        stages.last { $0.from <= time }?.performance.pose(at: time) ?? idle.pose(at: time)
    }
    let figure = idle.figure
    var found: [(frame: Int, pair: (arm: PartID, before: Pose, after: Pose))] = []
    let first = Int(((plays.first?.at ?? 0) * 60).rounded(.down))
    var before = pose(at: Double(first) / 60)
    for frame in first + 1...Int((end * 60).rounded(.up)) {
        let after = pose(at: Double(frame) / 60)
        for (index, part) in figure.parts.enumerated()
        where part.front && (after.parts[index].front >= 0.5) != (before.parts[index].front >= 0.5) {
            found.append((frame, (part.id, before, after)))
        }
        before = after
    }
    return found
}

/// The area where an arm's forearm covers the body, for a change of its depth
/// (`Figure.depthSwapShows`).
private func overlap(of arm: PartID, in figure: Figure, _ pose: Pose) throws -> Double {
    figure.depthSwapShows(try figure.index(arm), in: pose)
}

/// A clip that waits for an arm to clear the body waits only a moment, the clip before it going on
/// until then, and a clip played meanwhile replaces it.
@Test func aClipWaitsOnlyAMomentForAnArmToClear() throws {
    let kit = try #require(try PlaceholderCharacter.sportKits().kits.first { $0.id == "run" })
    let outfit = kit.dress(Outfit(["body": "peach", "top": "warmup-tee", "bottom": "warmup-shorts"]))
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    let run = try figure.bind(PlaceholderCharacter.move(for: kit, persona: .energetic))
    let bottle = try figure.bind(PlaceholderCharacter.signatureMove(wearing: outfit, persona: .energetic))
    var performance = Performance(figure: figure, idle: run)
    performance.play(bottle, at: 1.3)
    // Over the tee at 1.3 s, the run's arm clears it a few frames later.
    #expect(performance.clipName(at: 1.3) == run.clip.name)
    #expect(performance.pose(at: 1.3) == Performance(figure: figure, idle: run).pose(at: 1.3))
    #expect(performance.clipName(at: 1.3 + engineReach) == bottle.clip.name)
    let cheer = try figure.bind(
        PlaceholderCharacter.clip("cheer", persona: .energetic, species: PlaceholderCharacter.species(of: outfit)))
    performance.play(cheer, at: 1.31)
    #expect(
        stride(from: 1.31, through: 2.5, by: 1.0 / 60).allSatisfy { performance.clipName(at: $0) != bottle.clip.name })
}

/// How long `Performance` may hold a clip back (`DepthSwap.reach`, internal to the engine).
private let engineReach = 0.45

/// Picking a sport changes kits with a hop (`Performance.change`), from whatever kit's move is on
/// screen. Each swap from the squash, through the new kit's hop in, to its move stays clear of the
/// body too.
@Test(arguments: Persona.allCases)
func everyArmDepthSwapThroughAKitHopHappensClearOfTheBody(persona: Persona) throws {
    let kits = try PlaceholderCharacter.sportKits().kits
    let hop = try PlaceholderCharacter.kitHop()
    let base = Outfit(["body": "peach", "top": "warmup-tee", "bottom": "warmup-shorts"])
    var swaps = 0
    for kit in kits {
        let figure = try PlaceholderCharacter.figure(wearing: kit.dress(base))
        let idle = try figure.bind(PlaceholderCharacter.move(for: kit, persona: persona))
        for next in kits where next.id != kit.id {
            let dressed = try PlaceholderCharacter.figure(wearing: next.dress(base))
            let move = try dressed.bind(PlaceholderCharacter.move(for: next, persona: persona))
            for start in [0.37, 0.66, 1.24] {
                var performance = Performance(figure: figure, idle: idle)
                performance.change(
                    into: dressed, idle: move, leaving: try figure.bind(hop.out), arriving: try dressed.bind(hop.in),
                    at: start)
                let first = Int((start * 60).rounded(.down))
                var before = performance.pose(at: Double(first) / 60)
                for frame in first + 1...Int(((start + hop.out.duration + hop.in.duration + 0.8) * 60).rounded(.up)) {
                    let time = Double(frame) / 60
                    let (after, drawn) = (performance.pose(at: time), performance.figure(at: time))
                    // The outfit goes on between these two frames: compare each in its own drawing.
                    let was = performance.figure(at: Double(frame - 1) / 60)
                    for arm: PartID in ["armL", "armR"] {
                        let index = try drawn.index(arm)
                        guard (after.parts[index].front >= 0.5) != (before.parts[index].front >= 0.5) else { continue }
                        swaps += 1
                        let shown = try max(
                            drawn.depthSwapShows(index, in: after), was.depthSwapShows(was.index(arm), in: before))
                        #expect(
                            shown <= 16,
                            "\(kit.id) to \(next.id) as \(persona) from \(start)s swaps \(arm) at frame \(frame) over \(shown) pt²"
                        )
                    }
                    before = after
                }
            }
        }
    }
    #expect(swaps > 0)
}

/// Every top with its own arms, short sleeves and long.
private let topsWithSleeves: [String] = {
    let tops = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/AvatarArt/Placeholder/art/top").standardizedFileURL
    let names = (try? FileManager.default.contentsOfDirectory(atPath: tops.path(percentEncoded: false))) ?? []
    return names.filter {
        FileManager.default.fileExists(atPath: tops.appending(path: "\($0)/armL.svg").path(percentEncoded: false))
    }.sorted()
}()
